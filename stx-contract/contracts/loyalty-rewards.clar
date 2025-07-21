;; Loyalty Rewards Smart Contract
;; Implements SIP-010 fungible token standard for reward tokens
;; Allows merchants to create and manage loyalty programs

;; ===== CONSTANTS =====
(define-constant CONTRACT-OWNER tx-sender)
(define-constant ERR-OWNER-ONLY (err u100))
(define-constant ERR-NOT-TOKEN-OWNER (err u101))
(define-constant ERR-INSUFFICIENT-BALANCE (err u102))
(define-constant ERR-MERCHANT-NOT-FOUND (err u103))
(define-constant ERR-PROGRAM-INACTIVE (err u104))
(define-constant ERR-INVALID-AMOUNT (err u105))
(define-constant ERR-BELOW-MINIMUM-SPEND (err u106))
(define-constant ERR-EXCEEDS-MAX-REWARD (err u107))
(define-constant ERR-MERCHANT-EXISTS (err u108))
(define-constant ERR-INVALID-PARAMETERS (err u109))
(define-constant ERR-CONTRACT-PAUSED (err u110))

;; Token constants
(define-constant TOKEN-NAME "Loyalty Reward Token")
(define-constant TOKEN-SYMBOL "LRT")
(define-constant TOKEN-DECIMALS u6)
(define-constant TOKEN-URI u"https://loyalty-rewards.com/token-metadata")

;; Scaling factor for percentage calculations (1,000,000 = 100%)
(define-constant SCALE-FACTOR u1000000)

;; ===== DATA VARIABLES =====
(define-data-var token-total-supply uint u0)
(define-data-var contract-paused bool false)

;; ===== DATA MAPS =====

;; Token balances (SIP-010 requirement)
(define-map token-balances principal uint)

;; Token allowances for transfers
(define-map token-allowances {owner: principal, spender: principal} uint)

;; Merchant loyalty programs
(define-map merchant-programs
  principal
  {
    name: (string-ascii 50),
    reward-rate: uint,        ;; Scaled by SCALE-FACTOR (e.g., 50000 = 5%)
    minimum-spend: uint,      ;; Minimum spend to earn rewards (in microSTX)
    max-reward-per-tx: uint,  ;; Maximum reward per transaction
    is-active: bool,
    total-rewards-distributed: uint,
    created-at: uint
  }
)

;; User spending history per merchant
(define-map user-merchant-stats
  {user: principal, merchant: principal}
  {
    total-spent: uint,
    total-rewards-earned: uint,
    transaction-count: uint,
    last-transaction: uint
  }
)

;; Global user statistics
(define-map user-global-stats
  principal
  {
    total-spent-all-merchants: uint,
    total-rewards-earned-all-merchants: uint,
    total-transactions: uint,
    merchants-count: uint
  }
)

;; Transaction history for audit purposes
(define-map transaction-history
  uint
  {
    user: principal,
    merchant: principal,
    amount-spent: uint,
    rewards-earned: uint,
    timestamp: uint
  }
)

(define-data-var transaction-counter uint u0)

;; ===== SIP-010 FUNGIBLE TOKEN IMPLEMENTATION =====

(define-public (transfer (amount uint) (from principal) (to principal) (memo (optional (buff 34))))
  (begin
    (asserts! (or (is-eq from tx-sender) (is-eq from contract-caller)) ERR-NOT-TOKEN-OWNER)
    (asserts! (not (var-get contract-paused)) ERR-CONTRACT-PAUSED)
    (asserts! (> amount u0) ERR-INVALID-AMOUNT)
    
    (let ((from-balance (get-balance from)))
      (asserts! (>= from-balance amount) ERR-INSUFFICIENT-BALANCE)
      
      (map-set token-balances from (- from-balance amount))
      (map-set token-balances to (+ (get-balance to) amount))
      
      (print {action: "transfer", from: from, to: to, amount: amount, memo: memo})
      (ok true)
    )
  )
)

(define-read-only (get-name)
  (ok TOKEN-NAME)
)

(define-read-only (get-symbol)
  (ok TOKEN-SYMBOL)
)

(define-read-only (get-decimals)
  (ok TOKEN-DECIMALS)
)

(define-read-only (get-balance (who principal))
  (default-to u0 (map-get? token-balances who))
)

(define-read-only (get-total-supply)
  (ok (var-get token-total-supply))
)

(define-read-only (get-token-uri)
  (ok (some TOKEN-URI))
)

;; ===== MERCHANT PROGRAM MANAGEMENT =====

(define-public (register-merchant-program 
  (name (string-ascii 50))
  (reward-rate uint)
  (minimum-spend uint)
  (max-reward-per-tx uint)
)
  (begin
    (asserts! (not (var-get contract-paused)) ERR-CONTRACT-PAUSED)
    (asserts! (is-none (map-get? merchant-programs tx-sender)) ERR-MERCHANT-EXISTS)
    (asserts! (and (> reward-rate u0) (<= reward-rate u100000)) ERR-INVALID-PARAMETERS) ;; Max 10% reward rate
    (asserts! (> minimum-spend u0) ERR-INVALID-PARAMETERS)
    (asserts! (> max-reward-per-tx u0) ERR-INVALID-PARAMETERS)
    
    (map-set merchant-programs tx-sender {
      name: name,
      reward-rate: reward-rate,
      minimum-spend: minimum-spend,
      max-reward-per-tx: max-reward-per-tx,
      is-active: true,
      total-rewards-distributed: u0,
      created-at: stacks-block-height
    })
    
    (print {action: "merchant-registered", merchant: tx-sender, name: name})
    (ok true)
  )
)

(define-public (update-merchant-program
  (reward-rate uint)
  (minimum-spend uint)
  (max-reward-per-tx uint)
  (is-active bool)
)
  (begin
    (asserts! (not (var-get contract-paused)) ERR-CONTRACT-PAUSED)
    (asserts! (is-some (map-get? merchant-programs tx-sender)) ERR-MERCHANT-NOT-FOUND)
    (asserts! (and (> reward-rate u0) (<= reward-rate u100000)) ERR-INVALID-PARAMETERS)
    (asserts! (> minimum-spend u0) ERR-INVALID-PARAMETERS)
    (asserts! (> max-reward-per-tx u0) ERR-INVALID-PARAMETERS)
    
    (let ((current-program (unwrap! (map-get? merchant-programs tx-sender) ERR-MERCHANT-NOT-FOUND)))
      (map-set merchant-programs tx-sender (merge current-program {
        reward-rate: reward-rate,
        minimum-spend: minimum-spend,
        max-reward-per-tx: max-reward-per-tx,
        is-active: is-active
      }))
      
      (print {action: "merchant-updated", merchant: tx-sender})
      (ok true)
    )
  )
)

;; ===== REWARD PROCESSING =====

(define-public (process-payment-and-reward (merchant principal) (amount-spent uint))
  (begin
    (asserts! (not (var-get contract-paused)) ERR-CONTRACT-PAUSED)
    (asserts! (> amount-spent u0) ERR-INVALID-AMOUNT)
    
    (let (
      (program (unwrap! (map-get? merchant-programs merchant) ERR-MERCHANT-NOT-FOUND))
      (user tx-sender)
    )
      (asserts! (get is-active program) ERR-PROGRAM-INACTIVE)
      (asserts! (>= amount-spent (get minimum-spend program)) ERR-BELOW-MINIMUM-SPEND)
      
      (let (
        (calculated-reward (calculate-reward amount-spent (get reward-rate program)))
        (final-reward (if (> calculated-reward (get max-reward-per-tx program))
                        (get max-reward-per-tx program)
                        calculated-reward))
      )
        (asserts! (> final-reward u0) ERR-INVALID-AMOUNT)
        
        ;; Mint reward tokens
        (unwrap! (mint-tokens user final-reward) (err u500))
        
        ;; Update merchant program stats
        (map-set merchant-programs merchant 
          (merge program {
            total-rewards-distributed: (+ (get total-rewards-distributed program) final-reward)
          })
        )
        
        ;; Update user-merchant stats
        (update-user-merchant-stats user merchant amount-spent final-reward)
        
        ;; Update global user stats
        (update-user-global-stats user merchant amount-spent final-reward)
        
        ;; Record transaction
        (record-transaction user merchant amount-spent final-reward)
        
        (print {
          action: "reward-processed",
          user: user,
          merchant: merchant,
          amount-spent: amount-spent,
          rewards-earned: final-reward
        })
        
        (ok final-reward)
      )
    )
  )
)

(define-private (calculate-reward (amount uint) (rate uint))
  (/ (* amount rate) SCALE-FACTOR)
)

(define-private (mint-tokens (recipient principal) (amount uint))
  (begin
    (map-set token-balances recipient (+ (get-balance recipient) amount))
    (var-set token-total-supply (+ (var-get token-total-supply) amount))
    (ok true)
  )
)

;; ===== STATISTICS UPDATES =====

(define-private (update-user-merchant-stats (user principal) (merchant principal) (spent uint) (earned uint))
  (let (
    (current-stats (default-to 
      {total-spent: u0, total-rewards-earned: u0, transaction-count: u0, last-transaction: u0}
      (map-get? user-merchant-stats {user: user, merchant: merchant})
    ))
  )
    (map-set user-merchant-stats {user: user, merchant: merchant} {
      total-spent: (+ (get total-spent current-stats) spent),
      total-rewards-earned: (+ (get total-rewards-earned current-stats) earned),
      transaction-count: (+ (get transaction-count current-stats) u1),
      last-transaction: stacks-block-height
    })
  )
)

(define-private (update-user-global-stats (user principal) (merchant principal) (spent uint) (earned uint))
  (let (
    (current-stats (default-to 
      {total-spent-all-merchants: u0, total-rewards-earned-all-merchants: u0, total-transactions: u0, merchants-count: u0}
      (map-get? user-global-stats user)
    ))
    (is-new-merchant (is-none (map-get? user-merchant-stats {user: user, merchant: merchant})))
  )
    (map-set user-global-stats user {
      total-spent-all-merchants: (+ (get total-spent-all-merchants current-stats) spent),
      total-rewards-earned-all-merchants: (+ (get total-rewards-earned-all-merchants current-stats) earned),
      total-transactions: (+ (get total-transactions current-stats) u1),
      merchants-count: (if is-new-merchant 
                        (+ (get merchants-count current-stats) u1)
                        (get merchants-count current-stats))
    })
  )
)

(define-private (record-transaction (user principal) (merchant principal) (spent uint) (earned uint))
  (let ((tx-id (+ (var-get transaction-counter) u1)))
    (var-set transaction-counter tx-id)
    (map-set transaction-history tx-id {
      user: user,
      merchant: merchant,
      amount-spent: spent,
      rewards-earned: earned,
      timestamp: stacks-block-height
    })
  )
)

;; ===== BATCH REWARD DISTRIBUTION =====

(define-public (distribute-batch-rewards (recipients (list 50 {user: principal, amount: uint})))
  (begin
    (asserts! (not (var-get contract-paused)) ERR-CONTRACT-PAUSED)
    (asserts! (is-some (map-get? merchant-programs tx-sender)) ERR-MERCHANT-NOT-FOUND)
    
    (let ((program (unwrap! (map-get? merchant-programs tx-sender) ERR-MERCHANT-NOT-FOUND)))
      (asserts! (get is-active program) ERR-PROGRAM-INACTIVE)
      
      (let ((total-distributed (fold distribute-single-reward recipients u0)))
        (map-set merchant-programs tx-sender 
          (merge program {
            total-rewards-distributed: (+ (get total-rewards-distributed program) total-distributed)
          })
        )
        
        (print {action: "batch-rewards-distributed", merchant: tx-sender, total: total-distributed})
        (ok total-distributed)
      )
    )
  )
)

(define-private (distribute-single-reward (recipient {user: principal, amount: uint}) (acc uint))
  (begin
    (unwrap! (mint-tokens (get user recipient) (get amount recipient)) acc)
    (+ acc (get amount recipient))
  )
)

;; ===== ADMIN FUNCTIONS =====

(define-public (pause-contract)
  (begin
    (asserts! (is-eq tx-sender CONTRACT-OWNER) ERR-OWNER-ONLY)
    (var-set contract-paused true)
    (print {action: "contract-paused"})
    (ok true)
  )
)

(define-public (unpause-contract)
  (begin
    (asserts! (is-eq tx-sender CONTRACT-OWNER) ERR-OWNER-ONLY)
    (var-set contract-paused false)
    (print {action: "contract-unpaused"})
    (ok true)
  )
)

(define-public (emergency-pause-merchant (merchant principal))
  (begin
    (asserts! (is-eq tx-sender CONTRACT-OWNER) ERR-OWNER-ONLY)
    (asserts! (is-some (map-get? merchant-programs merchant)) ERR-MERCHANT-NOT-FOUND)
    
    (let ((program (unwrap! (map-get? merchant-programs merchant) ERR-MERCHANT-NOT-FOUND)))
      (map-set merchant-programs merchant (merge program {is-active: false}))
      (print {action: "merchant-emergency-paused", merchant: merchant})
      (ok true)
    )
  )
)

;; ===== READ-ONLY FUNCTIONS =====

(define-read-only (get-merchant-program (merchant principal))
  (map-get? merchant-programs merchant)
)

(define-read-only (get-user-merchant-stats (user principal) (merchant principal))
  (map-get? user-merchant-stats {user: user, merchant: merchant})
)

(define-read-only (get-user-global-stats (user principal))
  (map-get? user-global-stats user)
)

(define-read-only (get-transaction-history (tx-id uint))
  (map-get? transaction-history tx-id)
)

(define-read-only (calculate-potential-reward (merchant principal) (amount uint))
  (match (map-get? merchant-programs merchant)
    program (let (
      (calculated (calculate-reward amount (get reward-rate program)))
      (capped (if (> calculated (get max-reward-per-tx program))
                (get max-reward-per-tx program)
                calculated))
    )
      (if (and (get is-active program) (>= amount (get minimum-spend program)))
        (ok capped)
        (ok u0)
      )
    )
    ERR-MERCHANT-NOT-FOUND
  )
)

(define-read-only (is-contract-paused)
  (var-get contract-paused)
)

(define-read-only (get-transaction-count)
  (var-get transaction-counter)
)

;; ===== UTILITY FUNCTIONS =====

(define-public (burn (amount uint))
  (begin
    (asserts! (not (var-get contract-paused)) ERR-CONTRACT-PAUSED)
    (asserts! (> amount u0) ERR-INVALID-AMOUNT)
    
    (let ((sender-balance (get-balance tx-sender)))
      (asserts! (>= sender-balance amount) ERR-INSUFFICIENT-BALANCE)
      
      (map-set token-balances tx-sender (- sender-balance amount))
      (var-set token-total-supply (- (var-get token-total-supply) amount))
      
      (print {action: "tokens-burned", user: tx-sender, amount: amount})
      (ok true)
    )
  )
)

