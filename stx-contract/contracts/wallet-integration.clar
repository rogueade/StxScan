;; merchant-payment-system.clar
;; A smart contract for merchant wallet creation and QR code payment processing

;; Define data maps for storing merchant information
(define-map merchants
  { merchant-id: uint }
  {
    name: (string-utf8 100),
    wallet-address: principal,
    active: bool,
    created-at: uint
  }
)

;; Counter for merchant IDs
(define-data-var merchant-id-counter uint u0)

;; Define data map for payments
(define-map payments
  { payment-id: uint }
  {
    merchant-id: uint,
    amount: uint,
    token-type: (string-ascii 10),
    status: (string-ascii 20),
    timestamp: uint
  }
)

;; Counter for payment IDs
(define-data-var payment-id-counter uint u0)

;; Error codes
(define-constant ERR-NOT-AUTHORIZED u100)
(define-constant ERR-MERCHANT-NOT-FOUND u101)
(define-constant ERR-INVALID-QR-DATA u102)
(define-constant ERR-PAYMENT-FAILED u103)

;; Function to register a new merchant and create a wallet
(define-public (register-merchant (name (string-utf8 100)))
  (let
    (
      (new-merchant-id (+ (var-get merchant-id-counter) u1))
      (tx-sender tx-sender)
      (height stacks-block-height)
    )
    ;; Update merchant ID counter
    (var-set merchant-id-counter new-merchant-id)
    
    ;; Store merchant information
    (map-set merchants
      { merchant-id: new-merchant-id }
      {
        name: name,
        wallet-address: tx-sender,
        active: true,
        created-at: stacks-block-height
      }
    )
    
    ;; Return the new merchant ID and wallet address
    (ok { merchant-id: new-merchant-id, wallet-address: tx-sender })
  )
)

;; Function to encode payment details for QR code
(define-public (encode-payment-qr (merchant-id uint) (amount uint) (token-type (string-ascii 10)))
  (let
    (
      (merchant (unwrap! (map-get? merchants { merchant-id: merchant-id }) (err ERR-MERCHANT-NOT-FOUND)))
      (new-payment-id (+ (var-get payment-id-counter) u1))
    )
    
    ;; Check if merchant exists and is active
    (asserts! (get active merchant) (err ERR-MERCHANT-NOT-FOUND))
    
    ;; Update payment ID counter
    (var-set payment-id-counter new-payment-id)
    
    ;; Create payment record
    (map-set payments
      { payment-id: new-payment-id }
      {
        merchant-id: merchant-id,
        amount: amount,
        token-type: token-type,
        status: "pending",
        timestamp: stacks-block-height
      }
    )
    
    ;; Return encoded data for QR code
    ;; In a real implementation, this would be formatted for QR code generation
    (ok {
      payment-id: new-payment-id,
      merchant-id: merchant-id,
      merchant-wallet: (get wallet-address merchant),
      amount: amount,
      token-type: token-type
    })
  )
)

;; Function to decode QR code data and process payment
(define-public (process-payment-from-qr (payment-id uint) (token-type (string-ascii 10)))
  (let
    (
      (payment (unwrap! (map-get? payments { payment-id: payment-id }) (err ERR-INVALID-QR-DATA)))
      (merchant (unwrap! (map-get? merchants { merchant-id: (get merchant-id payment) }) (err ERR-MERCHANT-NOT-FOUND)))
      (payment-amount (get amount payment))
    )
    
    ;; Verify payment details
    (asserts! (is-eq (get token-type payment) token-type) (err ERR-INVALID-QR-DATA))
    
    ;; Process payment based on token type
    (if (is-eq token-type "STX")
      ;; For STX payments
      (let
        (
          (transfer-result (stx-transfer? payment-amount tx-sender (get wallet-address merchant)))
        )
        (if (is-ok transfer-result)
          (begin
            ;; Update payment status
            (map-set payments
              { payment-id: payment-id }
              (merge payment { status: "completed" })
            )
            (ok true)
          )
          (err ERR-PAYMENT-FAILED)
        )
      )
      ;; For other token types, you would implement token-specific transfers
      ;; This is a simplified example
      (err ERR-PAYMENT-FAILED)
    )
  )
)

;; Function for merchants to check their payments
(define-read-only (get-merchant-payments (merchant-id uint))
  (let
    (
      (merchant (map-get? merchants { merchant-id: merchant-id }))
    )
    (if (is-some merchant)
      (ok merchant-id)
      (err ERR-MERCHANT-NOT-FOUND)
    )
  )
)

;; Function to get merchant details
(define-read-only (get-merchant-details (merchant-id uint))
  (map-get? merchants { merchant-id: merchant-id })
)

;; Function to get payment details
(define-read-only (get-payment-details (payment-id uint))
  (map-get? payments { payment-id: payment-id })
)