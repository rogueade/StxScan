;; Refund and Dispute Resolution Contract
;; This contract handles payment refunds and decentralized dispute resolution

;; Constants
(define-constant CONTRACT_OWNER tx-sender)
(define-constant ERR_UNAUTHORIZED (err u100))
(define-constant ERR_PAYMENT_NOT_FOUND (err u101))
(define-constant ERR_ALREADY_REFUNDED (err u102))
(define-constant ERR_REFUND_PERIOD_EXPIRED (err u103))
(define-constant ERR_INSUFFICIENT_BALANCE (err u104))
(define-constant ERR_DISPUTE_NOT_FOUND (err u105))
(define-constant ERR_DISPUTE_ALREADY_RESOLVED (err u106))
(define-constant ERR_NOT_ARBITRATOR (err u107))
(define-constant ERR_INVALID_STATUS (err u108))

;; Time constants (in blocks)
(define-constant REFUND_PERIOD u1008) ;; ~7 days (assuming 10 min blocks)
(define-constant DISPUTE_PERIOD u2016) ;; ~14 days

;; Data Variables
(define-data-var next-payment-id uint u1)
(define-data-var next-dispute-id uint u1)
(define-data-var arbitration-fee uint u1000000) ;; 1 STX in microSTX

;; Payment status enum
(define-constant PAYMENT_ACTIVE u1)
(define-constant PAYMENT_COMPLETED u2)
(define-constant PAYMENT_REFUNDED u3)
(define-constant PAYMENT_DISPUTED u4)

;; Dispute status enum
(define-constant DISPUTE_OPEN u1)
(define-constant DISPUTE_IN_ARBITRATION u2)
(define-constant DISPUTE_RESOLVED_MERCHANT u3)
(define-constant DISPUTE_RESOLVED_CUSTOMER u4)

;; Data Maps
(define-map payments
  { payment-id: uint }
  {
    merchant: principal,
    customer: principal,
    amount: uint,
    description: (string-utf8 256),
    status: uint,
    created-at: uint,
    refund-deadline: uint
  }
)

(define-map disputes
  { dispute-id: uint }
  {
    payment-id: uint,
    initiator: principal,
    reason: (string-utf8 512),
    status: uint,
    arbitrator: (optional principal),
    created-at: uint,
    resolved-at: (optional uint),
    resolution: (optional (string-utf8 512))
  }
)

(define-map arbitrators
  { arbitrator: principal }
  {
    reputation-score: uint,
    cases-handled: uint,
    is-active: bool
  }
)

(define-map arbitrator-stakes
  { arbitrator: principal }
  { staked-amount: uint }
)

;; Payment Functions

;; Create a new payment
(define-public (create-payment (merchant principal) (amount uint) (description (string-utf8 256)))
  (let ((payment-id (var-get next-payment-id))
        (current-block stacks-block-height))
    (begin
      (map-set payments
        { payment-id: payment-id }
        {
          merchant: merchant,
          customer: tx-sender,
          amount: amount,
          description: description,
          status: PAYMENT_ACTIVE,
          created-at: current-block,
          refund-deadline: (+ current-block REFUND_PERIOD)
        }
      )
      (var-set next-payment-id (+ payment-id u1))
      (ok payment-id)
    )
  )
)

;; Process payment (transfer funds to merchant)
(define-public (process-payment (payment-id uint))
  (let ((payment-data (unwrap! (map-get? payments { payment-id: payment-id }) ERR_PAYMENT_NOT_FOUND)))
    (asserts! (is-eq tx-sender (get customer payment-data)) ERR_UNAUTHORIZED)
    (asserts! (is-eq (get status payment-data) PAYMENT_ACTIVE) ERR_INVALID_STATUS)
    (try! (stx-transfer? (get amount payment-data) tx-sender (get merchant payment-data)))
    (map-set payments
      { payment-id: payment-id }
      (merge payment-data { status: PAYMENT_COMPLETED })
    )
    (ok true)
  )
)

;; Request refund (can be called by merchant or customer)
(define-public (request-refund (payment-id uint) (reason (string-utf8 256)))
  (let ((payment-data (unwrap! (map-get? payments { payment-id: payment-id }) ERR_PAYMENT_NOT_FOUND)))
    (asserts! (or (is-eq tx-sender (get merchant payment-data))
                  (is-eq tx-sender (get customer payment-data))) ERR_UNAUTHORIZED)
    (asserts! (not (is-eq (get status payment-data) PAYMENT_REFUNDED)) ERR_ALREADY_REFUNDED)
    (asserts! (<= stacks-block-height (get refund-deadline payment-data)) ERR_REFUND_PERIOD_EXPIRED)
    
    ;; Process refund if merchant initiates or if within grace period
    (if (is-eq tx-sender (get merchant payment-data))
    (process-refund-internal payment-id)
    (ok false) ;; Return a boolean to match the true branch
)
  )
)

;; Internal refund processing
(define-private (process-refund-internal (payment-id uint))
  (let ((payment-data (unwrap! (map-get? payments { payment-id: payment-id }) ERR_PAYMENT_NOT_FOUND)))
    (try! (stx-transfer? (get amount payment-data) (get merchant payment-data) (get customer payment-data)))
    (map-set payments
      { payment-id: payment-id }
      (merge payment-data { status: PAYMENT_REFUNDED })
    )
    (ok true)
  )
)

;; Dispute Resolution Functions

;; Initiate a dispute
(define-public (initiate-dispute (payment-id uint) (reason (string-utf8 512)))
  (let ((payment-data (unwrap! (map-get? payments { payment-id: payment-id }) ERR_PAYMENT_NOT_FOUND))
        (dispute-id (var-get next-dispute-id)))
    (asserts! (or (is-eq tx-sender (get merchant payment-data))
                  (is-eq tx-sender (get customer payment-data))) ERR_UNAUTHORIZED)
    (asserts! (is-eq (get status payment-data) PAYMENT_COMPLETED) ERR_INVALID_STATUS)
    
    ;; Create dispute record
    (map-set disputes
      { dispute-id: dispute-id }
      {
        payment-id: payment-id,
        initiator: tx-sender,
        reason: reason,
        status: DISPUTE_OPEN,
        arbitrator: none,
        created-at: stacks-block-height,
        resolved-at: none,
        resolution: none
      }
    )
    
    ;; Update payment status
    (map-set payments
      { payment-id: payment-id }
      (merge payment-data { status: PAYMENT_DISPUTED })
    )
    
    (var-set next-dispute-id (+ dispute-id u1))
    (ok dispute-id)
  )
)

;; Accept arbitration case (arbitrator volunteers)
(define-public (accept-arbitration (dispute-id uint))
  (let ((dispute-data (unwrap! (map-get? disputes { dispute-id: dispute-id }) ERR_DISPUTE_NOT_FOUND))
        (arbitrator-data (unwrap! (map-get? arbitrators { arbitrator: tx-sender }) ERR_NOT_ARBITRATOR)))
    (asserts! (get is-active arbitrator-data) ERR_NOT_ARBITRATOR)
    (asserts! (is-eq (get status dispute-data) DISPUTE_OPEN) ERR_DISPUTE_ALREADY_RESOLVED)
    (asserts! (is-none (get arbitrator dispute-data)) ERR_DISPUTE_ALREADY_RESOLVED)
    
    ;; Require arbitration fee to be staked
    (try! (stx-transfer? (var-get arbitration-fee) tx-sender (as-contract tx-sender)))
    
    ;; Assign arbitrator and update status
    (map-set disputes
      { dispute-id: dispute-id }
      (merge dispute-data {
        arbitrator: (some tx-sender),
        status: DISPUTE_IN_ARBITRATION
      })
    )
    
    (ok true)
  )
)

;; Arbitrator Management Functions

;; Register as arbitrator
(define-public (register-arbitrator (stake-amount uint))
  (begin
    (asserts! (>= stake-amount u10000000) (err u109)) ;; Minimum 10 STX stake
    (try! (stx-transfer? stake-amount tx-sender (as-contract tx-sender)))
    
    (map-set arbitrators
      { arbitrator: tx-sender }
      {
        reputation-score: u100, ;; Starting score
        cases-handled: u0,
        is-active: true
      }
    )
    
    (map-set arbitrator-stakes
      { arbitrator: tx-sender }
      { staked-amount: stake-amount }
    )
    
    (ok true)
  )
)

;; Update arbitrator statistics
(define-private (update-arbitrator-stats (arbitrator principal))
  (let ((current-stats (unwrap! (map-get? arbitrators { arbitrator: arbitrator }) ERR_NOT_ARBITRATOR)))
    (map-set arbitrators
      { arbitrator: arbitrator }
      (merge current-stats {
        cases-handled: (+ (get cases-handled current-stats) u1),
        reputation-score: (+ (get reputation-score current-stats) u10) ;; Simple reputation increase
      })
    )
    (ok true)
  )
)

;; Read-only Functions

;; Get payment details
(define-read-only (get-payment (payment-id uint))
  (map-get? payments { payment-id: payment-id })
)

;; Get dispute details
(define-read-only (get-dispute (dispute-id uint))
  (map-get? disputes { dispute-id: dispute-id })
)

;; Get arbitrator info
(define-read-only (get-arbitrator (arbitrator principal))
  (map-get? arbitrators { arbitrator: arbitrator })
)

;; Check if refund is possible
(define-read-only (can-refund (payment-id uint))
  (match (map-get? payments { payment-id: payment-id })
    payment-data (and 
      (not (is-eq (get status payment-data) PAYMENT_REFUNDED))
      (<= stacks-block-height (get refund-deadline payment-data))
    )
    false
  )
)

;; Get contract stats
(define-read-only (get-contract-stats)
  {
    total-payments: (- (var-get next-payment-id) u1),
    total-disputes: (- (var-get next-dispute-id) u1),
    arbitration-fee: (var-get arbitration-fee)
  }
)

;; Admin Functions (Contract Owner Only)

;; Update arbitration fee
(define-public (set-arbitration-fee (new-fee uint))
  (begin
    (asserts! (is-eq tx-sender CONTRACT_OWNER) ERR_UNAUTHORIZED)
    (var-set arbitration-fee new-fee)
    (ok true)
  )
)

;; Deactivate arbitrator (for misconduct)
(define-public (deactivate-arbitrator (arbitrator principal))
  (let ((arbitrator-data (unwrap! (map-get? arbitrators { arbitrator: arbitrator }) ERR_NOT_ARBITRATOR)))
    (asserts! (is-eq tx-sender CONTRACT_OWNER) ERR_UNAUTHORIZED)
    (map-set arbitrators
      { arbitrator: arbitrator }
      (merge arbitrator-data { is-active: false })
    )
    (ok true)
  )
)