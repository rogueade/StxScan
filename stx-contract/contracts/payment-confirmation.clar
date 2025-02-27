;; Payment Confirmation & Notifications Smart Contract
;; This contract handles payment confirmations and status tracking

;; Define constants for payment statuses
(define-constant PENDING u0)
(define-constant COMPLETED u1)
(define-constant FAILED u2)

;; Data maps to store payment information
(define-map payments
  { payment-id: (buff 32) }
  {
    sender: principal,
    recipient: principal,
    amount: uint,
    status: uint,
    timestamp: uint
  }
)

;; Map to track notifications for each user
(define-map user-notifications
  { user: principal }
  { notification-count: uint }
)

;; Events for on-chain notifications
(define-public (payment-status-changed (payment-id (buff 32)) (new-status uint))
  (begin
    (print { event: "payment-status-changed", payment-id: payment-id, status: new-status })
    (ok true)
  )
)

;; Function to increment notification count
(define-public (increment-notification-count (user principal))
  (let
    (
      (current-notifications (default-to { notification-count: u0 } (map-get? user-notifications { user: user })))
      (current-count (get notification-count current-notifications))
    )
    (map-set user-notifications
      { user: user }
      { notification-count: (+ current-count u1) }
    )
    (ok true)
  )
)

;; Create a new payment
(define-public (create-payment (payment-id (buff 32)) (recipient principal) (amount uint))
  (let
    (
      (sender tx-sender)
      (current-time stacks-block-height)
    )
    (asserts! (> amount u0) (err u2))
    
    ;; Check if payment already exists
    (asserts! (is-none (map-get? payments { payment-id: payment-id })) (err u3))
    
    ;; Store the payment with PENDING status
    (map-set payments
      { payment-id: payment-id }
      {
        sender: sender,
        recipient: recipient,
        amount: amount,
        status: PENDING,
        timestamp: current-time
      }
    )
    
    ;; Emit event for payment creation
    (print { event: "payment-created", payment-id: payment-id, sender: sender, recipient: recipient, amount: amount })
    
    ;; Increment notification count for both parties
    (unwrap! (increment-notification-count sender) (err u1))
    (unwrap! (increment-notification-count recipient) (err u1))
    
    (ok true)
  )
)

;; Process a payment (mark as completed)
(define-public (complete-payment (payment-id (buff 32)))
  (let
    (
      (payment (unwrap! (map-get? payments { payment-id: payment-id }) (err u4)))
      (sender (get sender payment))
      (recipient (get recipient payment))
    )
    ;; Only the sender can complete the payment
    (asserts! (is-eq tx-sender sender) (err u5))
    
    ;; Check that payment is in PENDING status
    (asserts! (is-eq (get status payment) PENDING) (err u6))
    
    ;; Update payment status to COMPLETED
    (map-set payments
      { payment-id: payment-id }
      (merge payment { status: COMPLETED })
    )
    
    ;; Emit status change event
    (unwrap! (payment-status-changed payment-id COMPLETED) (err u4))
    
    ;; Increment notification count for both parties
    (unwrap! (increment-notification-count sender) (err u1))
    (unwrap! (increment-notification-count recipient) (err u1))
    
    (ok true)
  )
)

;; Mark a payment as failed
(define-public (fail-payment (payment-id (buff 32)))
  (let
    (
      (payment (unwrap! (map-get? payments { payment-id: payment-id }) (err u4)))
      (sender (get sender payment))
      (recipient (get recipient payment))
    )
    ;; Only the sender can mark a payment as failed
    (asserts! (is-eq tx-sender sender) (err u5))
    
    ;; Check that payment is in PENDING status
    (asserts! (is-eq (get status payment) PENDING) (err u6))
    
    ;; Update payment status to FAILED
    (map-set payments
      { payment-id: payment-id }
      (merge payment { status: FAILED })
    )
    
    ;; Emit status change event
    (unwrap! (payment-status-changed payment-id FAILED) (err u4))

    
    ;; Increment notification count for both parties
    (unwrap! (increment-notification-count sender) (err u1))
    (unwrap! (increment-notification-count recipient) (err u1))
    
    (ok true)
  )
)

;; Get payment details
(define-read-only (get-payment (payment-id (buff 32)))
  (map-get? payments { payment-id: payment-id })
)

;; Get payment status
(define-read-only (get-payment-status (payment-id (buff 32)))
  (match (map-get? payments { payment-id: payment-id })
    payment (ok (get status payment))
    (err u4)
  )
)

;; Get notification count for a user
(define-read-only (get-notification-count (user principal))
  (default-to { notification-count: u0 } (map-get? user-notifications { user: user }))
)

;; Reset notification count for a user
(define-public (reset-notifications)
  (begin
    (map-set user-notifications
      { user: tx-sender }
      { notification-count: u0 }
    )
    (ok true)
  )
)