;; Subscription/Recurring Payments Smart Contract
;; Enables merchants to offer subscription services with automatic recurring payments

;; Constants
(define-constant contract-owner tx-sender)
(define-constant err-owner-only (err u100))
(define-constant err-not-found (err u101))
(define-constant err-unauthorized (err u102))
(define-constant err-invalid-amount (err u103))
(define-constant err-subscription-inactive (err u104))
(define-constant err-insufficient-balance (err u105))
(define-constant err-payment-failed (err u106))
(define-constant err-already-subscribed (err u107))
(define-constant err-invalid-interval (err u108))

;; Data Variables
(define-data-var next-subscription-id uint u1)
(define-data-var next-plan-id uint u1)

;; Data Maps
;; Subscription Plans
(define-map subscription-plans
  { plan-id: uint }
  {
    merchant: principal,
    name: (string-ascii 50),
    description: (string-ascii 200),
    price: uint,
    interval-type: (string-ascii 10), ;; "weekly", "monthly", "yearly"
    interval-count: uint, ;; number of blocks for interval
    is-active: bool,
    created-at: uint
  }
)

;; User Subscriptions
(define-map user-subscriptions
  { subscription-id: uint }
  {
    subscriber: principal,
    plan-id: uint,
    merchant: principal,
    status: (string-ascii 10), ;; "active", "paused", "cancelled"
    next-payment-block: uint,
    total-payments: uint,
    created-at: uint,
    updated-at: uint
  }
)

;; Payment History
(define-map payment-history
  { payment-id: uint }
  {
    subscription-id: uint,
    subscriber: principal,
    merchant: principal,
    amount: uint,
    block-height: uint,
    status: (string-ascii 10) ;; "success", "failed"
  }
)

;; User's active subscriptions (for quick lookup)
(define-map user-active-subscriptions
  { subscriber: principal, plan-id: uint }
  { subscription-id: uint }
)

;; Payment counter
(define-data-var next-payment-id uint u1)

;; Read-only functions

;; Get subscription plan details
(define-read-only (get-subscription-plan (plan-id uint))
  (map-get? subscription-plans { plan-id: plan-id })
)

;; Get user subscription details
(define-read-only (get-user-subscription (subscription-id uint))
  (map-get? user-subscriptions { subscription-id: subscription-id })
)

;; Get payment history
(define-read-only (get-payment-details (payment-id uint))
  (map-get? payment-history { payment-id: payment-id })
)

;; Check if user has active subscription for a plan
(define-read-only (has-active-subscription (subscriber principal) (plan-id uint))
  (is-some (map-get? user-active-subscriptions { subscriber: subscriber, plan-id: plan-id }))
)

;; Get user's subscription ID for a plan
(define-read-only (get-user-subscription-id (subscriber principal) (plan-id uint))
  (map-get? user-active-subscriptions { subscriber: subscriber, plan-id: plan-id })
)

;; Public functions

;; Create a new subscription plan (merchant only)
(define-public (create-subscription-plan 
  (name (string-ascii 50))
  (description (string-ascii 200))
  (price uint)
  (interval-type (string-ascii 10))
  (interval-count uint))
  (let
    (
      (plan-id (var-get next-plan-id))
    )
    (asserts! (> price u0) err-invalid-amount)
    (asserts! (> interval-count u0) err-invalid-interval)
    (asserts! (or (is-eq interval-type "weekly") 
                  (is-eq interval-type "monthly") 
                  (is-eq interval-type "yearly")) err-invalid-interval)
    
    (map-set subscription-plans
      { plan-id: plan-id }
      {
        merchant: tx-sender,
        name: name,
        description: description,
        price: price,
        interval-type: interval-type,
        interval-count: interval-count,
        is-active: true,
        created-at: stacks-block-height
      }
    )
    
    (var-set next-plan-id (+ plan-id u1))
    (ok plan-id)
  )
)

;; Subscribe to a plan
(define-public (subscribe-to-plan (plan-id uint))
  (let
    (
      (plan (unwrap! (get-subscription-plan plan-id) err-not-found))
      (subscription-id (var-get next-subscription-id))
      (next-payment (+ stacks-block-height (get interval-count plan)))
    )
    (asserts! (get is-active plan) err-subscription-inactive)
    (asserts! (not (has-active-subscription tx-sender plan-id)) err-already-subscribed)
    (asserts! (>= (stx-get-balance tx-sender) (get price plan)) err-insufficient-balance)
    
    ;; Process initial payment
    (try! (stx-transfer? (get price plan) tx-sender (get merchant plan)))
    
    ;; Create subscription record
    (map-set user-subscriptions
      { subscription-id: subscription-id }
      {
        subscriber: tx-sender,
        plan-id: plan-id,
        merchant: (get merchant plan),
        status: "active",
        next-payment-block: next-payment,
        total-payments: u1,
        created-at: stacks-block-height,
        updated-at: stacks-block-height
      }
    )
    
    ;; Add to active subscriptions lookup
    (map-set user-active-subscriptions
      { subscriber: tx-sender, plan-id: plan-id }
      { subscription-id: subscription-id }
    )
    
    ;; Record payment
    (record-payment subscription-id tx-sender (get merchant plan) (get price plan) "success")
    
    (var-set next-subscription-id (+ subscription-id u1))
    (ok subscription-id)
  )
)

;; Process recurring payment
(define-public (process-recurring-payment (subscription-id uint))
  (let
    (
      (subscription (unwrap! (get-user-subscription subscription-id) err-not-found))
      (plan (unwrap! (get-subscription-plan (get plan-id subscription)) err-not-found))
    )
    (asserts! (is-eq (get status subscription) "active") err-subscription-inactive)
    (asserts! (<= (get next-payment-block subscription) stacks-block-height) err-unauthorized)
    (asserts! (>= (stx-get-balance (get subscriber subscription)) (get price plan)) err-insufficient-balance)
    
    ;; Process payment
    (match (stx-transfer? (get price plan) (get subscriber subscription) (get merchant subscription))
      success (begin
        ;; Update subscription
        (map-set user-subscriptions
          { subscription-id: subscription-id }
          (merge subscription {
            next-payment-block: (+ stacks-block-height (get interval-count plan)),
            total-payments: (+ (get total-payments subscription) u1),
            updated-at: stacks-block-height
          })
        )
        
        ;; Record successful payment
        (record-payment subscription-id (get subscriber subscription) (get merchant subscription) (get price plan) "success")
        (ok true)
      )
      error (begin
        ;; Record failed payment
        (record-payment subscription-id (get subscriber subscription) (get merchant subscription) (get price plan) "failed")
        err-payment-failed
      )
    )
  )
)

;; Pause subscription
(define-public (pause-subscription (subscription-id uint))
  (let
    (
      (subscription (unwrap! (get-user-subscription subscription-id) err-not-found))
    )
    (asserts! (is-eq tx-sender (get subscriber subscription)) err-unauthorized)
    (asserts! (is-eq (get status subscription) "active") err-subscription-inactive)
    
    (map-set user-subscriptions
      { subscription-id: subscription-id }
      (merge subscription {
        status: "paused",
        updated-at: stacks-block-height
      })
    )
    
    (ok true)
  )
)

;; Resume subscription
(define-public (resume-subscription (subscription-id uint))
  (let
    (
      (subscription (unwrap! (get-user-subscription subscription-id) err-not-found))
      (plan (unwrap! (get-subscription-plan (get plan-id subscription)) err-not-found))
    )
    (asserts! (is-eq tx-sender (get subscriber subscription)) err-unauthorized)
    (asserts! (is-eq (get status subscription) "paused") err-subscription-inactive)
    
    (map-set user-subscriptions
      { subscription-id: subscription-id }
      (merge subscription {
        status: "active",
        next-payment-block: (+ stacks-block-height (get interval-count plan)),
        updated-at: stacks-block-height
      })
    )
    
    (ok true)
  )
)

;; Cancel subscription
(define-public (cancel-subscription (subscription-id uint))
  (let
    (
      (subscription (unwrap! (get-user-subscription subscription-id) err-not-found))
    )
    (asserts! (is-eq tx-sender (get subscriber subscription)) err-unauthorized)
    (asserts! (not (is-eq (get status subscription) "cancelled")) err-subscription-inactive)
    
    ;; Update subscription status
    (map-set user-subscriptions
      { subscription-id: subscription-id }
      (merge subscription {
        status: "cancelled",
        updated-at: stacks-block-height
      })
    )
    
    ;; Remove from active subscriptions lookup
    (map-delete user-active-subscriptions
      { subscriber: (get subscriber subscription), plan-id: (get plan-id subscription) }
    )
    
    (ok true)
  )
)

;; Deactivate subscription plan (merchant only)
(define-public (deactivate-plan (plan-id uint))
  (let
    (
      (plan (unwrap! (get-subscription-plan plan-id) err-not-found))
    )
    (asserts! (is-eq tx-sender (get merchant plan)) err-unauthorized)
    
    (map-set subscription-plans
      { plan-id: plan-id }
      (merge plan { is-active: false })
    )
    
    (ok true)
  )
)

;; Private functions

;; Record payment in history
(define-private (record-payment 
  (subscription-id uint)
  (subscriber principal)
  (merchant principal)
  (amount uint)
  (status (string-ascii 10)))
  (let
    (
      (payment-id (var-get next-payment-id))
    )
    (map-set payment-history
      { payment-id: payment-id }
      {
        subscription-id: subscription-id,
        subscriber: subscriber,
        merchant: merchant,
        amount: amount,
        block-height: stacks-block-height,
        status: status
      }
    )
    
    (var-set next-payment-id (+ payment-id u1))
    payment-id
  )
)

;; Batch process recurring payments (can be called by anyone to trigger payments)
(define-public (batch-process-payments (subscription-ids (list 50 uint)))
  (ok (map process-single-payment subscription-ids))
)

;; Helper function for batch processing
(define-private (process-single-payment (subscription-id uint))
  (match (process-recurring-payment subscription-id)
    success true
    error false
  )
)
