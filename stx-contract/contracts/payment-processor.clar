;; Define constants for supported currencies
(define-constant ERR_INVALID_CURRENCY (err u100))
(define-constant ERR_INSUFFICIENT_BALANCE (err u101))
(define-constant ERR_UNAUTHORIZED (err u102))
(define-constant ERR_MAX_CURRENCIES_REACHED (err u103))

;; Define contract owner
(define-data-var contract-owner principal tx-sender)

;; Define trait for fungible tokens (currencies)
(define-trait fungible-token
  (
    (transfer (uint principal principal) (response bool uint))
  )
)

;; Define supported currencies
(define-data-var supported-currencies (list 10 principal) (list))

;; Map to store merchant wallet addresses
(define-map merchants principal principal)

;; Function to add supported currencies (only contract owner can do this)
(define-public (add-supported-currency (currency principal))
    (begin
        (asserts! (is-eq tx-sender (var-get contract-owner)) ERR_UNAUTHORIZED)
        (asserts! (< (len (var-get supported-currencies)) u10) ERR_MAX_CURRENCIES_REACHED)
        (var-set supported-currencies (unwrap! (as-max-len? (append (var-get supported-currencies) currency) u10) ERR_UNAUTHORIZED))
        (ok true)
    )
)

;; Function to register a merchant
(define-public (register-merchant (merchant-wallet principal))
    (begin
        (map-set merchants tx-sender merchant-wallet)
        (print {event: "merchant-registered", merchant: tx-sender, wallet: merchant-wallet})
        (ok true)
    )
)

;; Function to process payment
(define-public (process-payment (merchant principal) (amount uint) (currency <fungible-token>))
    (let
        (
            (merchant-wallet (unwrap! (map-get? merchants merchant) ERR_UNAUTHORIZED))
        )
        (asserts! (is-some (index-of (var-get supported-currencies) (contract-of currency))) ERR_INVALID_CURRENCY)
        (match (contract-call? currency transfer amount tx-sender merchant-wallet)
            success
                (begin
                    (print {event: "payment-processed", merchant: merchant, amount: amount, currency: (contract-of currency)})
                    (ok true)
                )
            error ERR_INSUFFICIENT_BALANCE
        )
    )
)

;; Read-only function to check if a currency is supported
(define-read-only (is-currency-supported (currency principal))
    (is-some (index-of (var-get supported-currencies) currency))
)

;; Read-only function to get a merchant's wallet address
(define-read-only (get-merchant-wallet (merchant principal))
    (map-get? merchants merchant)
)

;; Function to change contract owner (only current owner can do this)
(define-public (change-contract-owner (new-owner principal))
    (begin
        (asserts! (is-eq tx-sender (var-get contract-owner)) ERR_UNAUTHORIZED)
        (var-set contract-owner new-owner)
        (ok true)
    )
)

;; Read-only function to get the current contract owner
(define-read-only (get-contract-owner)
    (var-get contract-owner)
)

;; Read-only function to get the list of supported currencies
(define-read-only (get-supported-currencies)
    (var-get supported-currencies)
)