
;; title: fee-management
;; version:
;; summary:
;; description:

;; Define constants
(define-constant contract-owner tx-sender)
(define-constant err-owner-only (err u100))
(define-constant err-invalid-fee (err u101))

;; Define data vars
(define-data-var fee-wallet principal 'ST1PQHQKV0RJXZFY1DGX8MNSNYVE3VGZJSRTPGZGM)
(define-data-var default-fee-rate uint u250) ;; 2.5% (stored as basis points)

;; Define data maps
(define-map merchant-fees principal uint)

;; Define read-only functions
(define-read-only (get-merchant-fee (merchant principal))
  (default-to (var-get default-fee-rate) (map-get? merchant-fees merchant))
)

;; Define public functions
(define-public (set-merchant-fee (fee uint))
  (begin
    (asserts! (<= fee u10000) err-invalid-fee) ;; Max fee is 100% (10000 basis points)
    (ok (map-set merchant-fees tx-sender fee))
  )
)

(define-public (process-payment (amount uint) (merchant principal))
  (let
    (
      (fee-rate (get-merchant-fee merchant))
      (fee-amount (/ (* amount fee-rate) u10000))
      (merchant-amount (- amount fee-amount))
    )
    (begin
      ;; Transfer fee to fee wallet
      (try! (stx-transfer? fee-amount tx-sender (var-get fee-wallet)))
      ;; Transfer remaining amount to merchant
      (try! (stx-transfer? merchant-amount tx-sender merchant))
      (ok true)
    )
  )
)

;; Define private functions
(define-private (is-contract-owner)
  (is-eq tx-sender contract-owner)
)

;; Define admin functions
(define-public (set-default-fee-rate (new-rate uint))
  (begin
    (asserts! (is-contract-owner) err-owner-only)
    (asserts! (<= new-rate u10000) err-invalid-fee)
    (ok (var-set default-fee-rate new-rate))
  )
)

(define-public (set-fee-wallet (new-wallet principal))
  (begin
    (asserts! (is-contract-owner) err-owner-only)
    (ok (var-set fee-wallet new-wallet))
  )
)