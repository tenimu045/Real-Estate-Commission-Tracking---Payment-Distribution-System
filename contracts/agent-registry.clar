;; Agent Registry Contract
;; Manages agent registration, licensing, and profile information

;; Constants
(define-constant CONTRACT-OWNER tx-sender)
(define-constant ERR-NOT-AUTHORIZED (err u100))
(define-constant ERR-AGENT-EXISTS (err u101))
(define-constant ERR-AGENT-NOT-FOUND (err u102))
(define-constant ERR-INVALID-LICENSE (err u103))
(define-constant ERR-INVALID-INPUT (err u104))

;; Data Variables
(define-data-var next-agent-id uint u1)

;; Data Maps
(define-map agents
  { agent-id: uint }
  {
    principal: principal,
    license-number: (string-ascii 50),
    license-status: (string-ascii 20),
    broker-principal: (optional principal),
    registration-date: uint,
    total-transactions: uint,
    total-commission: uint,
    compliance-score: uint,
    is-active: bool
  }
)

(define-map agent-principals
  { principal: principal }
  { agent-id: uint }
)

(define-map brokers
  { broker-principal: principal }
  {
    broker-name: (string-ascii 100),
    license-number: (string-ascii 50),
    registration-date: uint,
    agent-count: uint,
    is-active: bool
  }
)

;; Public Functions

;; Register a new agent
(define-public (register-agent
  (license-number (string-ascii 50))
  (broker-principal (optional principal)))
  (let
    (
      (agent-id (var-get next-agent-id))
      (current-block-height block-height)
    )
    (asserts! (is-none (map-get? agent-principals { principal: tx-sender })) ERR-AGENT-EXISTS)
    (asserts! (> (len license-number) u0) ERR-INVALID-LICENSE)

    ;; Create agent record
    (map-set agents
      { agent-id: agent-id }
      {
        principal: tx-sender,
        license-number: license-number,
        license-status: "active",
        broker-principal: broker-principal,
        registration-date: current-block-height,
        total-transactions: u0,
        total-commission: u0,
        compliance-score: u100,
        is-active: true
      }
    )

    ;; Map principal to agent ID
    (map-set agent-principals
      { principal: tx-sender }
      { agent-id: agent-id }
    )

    ;; Update next agent ID
    (var-set next-agent-id (+ agent-id u1))

    ;; Update broker agent count if applicable
    (match broker-principal
      broker-addr (update-broker-agent-count broker-addr u1)
      true
    )

    (ok agent-id)
  )
)

;; Register a new broker
(define-public (register-broker
  (broker-name (string-ascii 100))
  (license-number (string-ascii 50)))
  (begin
    (asserts! (is-none (map-get? brokers { broker-principal: tx-sender })) ERR-AGENT-EXISTS)
    (asserts! (> (len broker-name) u0) ERR-INVALID-INPUT)
    (asserts! (> (len license-number) u0) ERR-INVALID-LICENSE)

    (map-set brokers
      { broker-principal: tx-sender }
      {
        broker-name: broker-name,
        license-number: license-number,
        registration-date: block-height,
        agent-count: u0,
        is-active: true
      }
    )

    (ok true)
  )
)

;; Update agent performance metrics
(define-public (update-agent-performance
  (agent-principal principal)
  (transaction-amount uint)
  (commission-amount uint))
  (let
    (
      (agent-lookup (map-get? agent-principals { principal: agent-principal }))
    )
    (asserts! (is-some agent-lookup) ERR-AGENT-NOT-FOUND)

    (let
      (
        (agent-id (get agent-id (unwrap-panic agent-lookup)))
        (current-agent (unwrap-panic (map-get? agents { agent-id: agent-id })))
      )
      (map-set agents
        { agent-id: agent-id }
        (merge current-agent
          {
            total-transactions: (+ (get total-transactions current-agent) u1),
            total-commission: (+ (get total-commission current-agent) commission-amount)
          }
        )
      )

      (ok true)
    )
  )
)

;; Update compliance score
(define-public (update-compliance-score
  (agent-principal principal)
  (new-score uint))
  (let
    (
      (agent-lookup (map-get? agent-principals { principal: agent-principal }))
    )
    (asserts! (is-some agent-lookup) ERR-AGENT-NOT-FOUND)
    (asserts! (<= new-score u100) ERR-INVALID-INPUT)

    (let
      (
        (agent-id (get agent-id (unwrap-panic agent-lookup)))
        (current-agent (unwrap-panic (map-get? agents { agent-id: agent-id })))
      )
      (map-set agents
        { agent-id: agent-id }
        (merge current-agent { compliance-score: new-score })
      )

      (ok true)
    )
  )
)

;; Read-only Functions

;; Get agent information by principal
(define-read-only (get-agent-by-principal (agent-principal principal))
  (match (map-get? agent-principals { principal: agent-principal })
    agent-lookup (map-get? agents { agent-id: (get agent-id agent-lookup) })
    none
  )
)

;; Get agent information by ID
(define-read-only (get-agent-by-id (agent-id uint))
  (map-get? agents { agent-id: agent-id })
)

;; Get broker information
(define-read-only (get-broker (broker-principal principal))
  (map-get? brokers { broker-principal: broker-principal })
)

;; Check if agent is active and compliant
(define-read-only (is-agent-compliant (agent-principal principal))
  (match (get-agent-by-principal agent-principal)
    agent-data (and
      (get is-active agent-data)
      (>= (get compliance-score agent-data) u70)
      (is-eq (get license-status agent-data) "active")
    )
    false
  )
)

;; Private Functions

;; Update broker agent count
(define-private (update-broker-agent-count (broker-principal principal) (increment uint))
  (match (map-get? brokers { broker-principal: broker-principal })
    broker-data (map-set brokers
      { broker-principal: broker-principal }
      (merge broker-data { agent-count: (+ (get agent-count broker-data) increment) })
    )
    false
  )
)
