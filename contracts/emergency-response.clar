;; Emergency Response Contract
;; Manages traffic incident response and emergency protocols

(define-constant CONTRACT_OWNER tx-sender)
(define-constant ERR_UNAUTHORIZED (err u500))
(define-constant ERR_INVALID_EMERGENCY (err u501))
(define-constant ERR_NOT_FOUND (err u502))
(define-constant ERR_ALREADY_RESPONDED (err u503))

;; Emergency types
(define-constant EMERGENCY_ACCIDENT u1)
(define-constant EMERGENCY_BREAKDOWN u2)
(define-constant EMERGENCY_WEATHER u3)
(define-constant EMERGENCY_ROAD_CLOSURE u4)
(define-constant EMERGENCY_MEDICAL u5)

;; Emergency status
(define-constant STATUS_REPORTED u1)
(define-constant STATUS_DISPATCHED u2)
(define-constant STATUS_ON_SCENE u3)
(define-constant STATUS_RESOLVED u4)

;; Emergency incidents
(define-map emergency-incidents
  { emergency-id: uint }
  {
    reporter: principal,
    emergency-type: uint,
    location: (string-ascii 100),
    description: (string-ascii 200),
    severity: uint,
    status: uint,
    reported-time: uint,
    response-time: uint,
    resolved-time: uint,
    responder: (optional principal)
  }
)

;; Emergency responders
(define-map emergency-responders
  principal
  {
    responder-type: (string-ascii 30),
    active: bool,
    current-emergency: (optional uint),
    total-responses: uint
  }
)

;; Traffic diversions
(define-map traffic-diversions
  { diversion-id: uint }
  {
    emergency-id: uint,
    affected-zone: uint,
    diversion-route: (string-ascii 200),
    active: bool,
    created-time: uint
  }
)

(define-data-var next-emergency-id uint u1)
(define-data-var next-diversion-id uint u1)

;; Responder management
(define-public (register-responder (responder-type (string-ascii 30)))
  (begin
    (map-set emergency-responders
      tx-sender
      {
        responder-type: responder-type,
        active: true,
        current-emergency: none,
        total-responses: u0
      }
    )
    (ok true)
  )
)

(define-public (deactivate-responder)
  (let ((responder (unwrap! (map-get? emergency-responders tx-sender) ERR_NOT_FOUND)))
    (map-set emergency-responders
      tx-sender
      (merge responder { active: false })
    )
    (ok true)
  )
)

;; Emergency reporting
(define-public (report-emergency
  (emergency-type uint)
  (location (string-ascii 100))
  (description (string-ascii 200))
  (severity uint)
)
  (let ((emergency-id (var-get next-emergency-id)))
    (asserts! (and (>= emergency-type EMERGENCY_ACCIDENT) (<= emergency-type EMERGENCY_MEDICAL)) ERR_INVALID_EMERGENCY)
    (asserts! (and (>= severity u1) (<= severity u5)) ERR_INVALID_EMERGENCY)
    (map-set emergency-incidents
      { emergency-id: emergency-id }
      {
        reporter: tx-sender,
        emergency-type: emergency-type,
        location: location,
        description: description,
        severity: severity,
        status: STATUS_REPORTED,
        reported-time: block-height,
        response-time: u0,
        resolved-time: u0,
        responder: none
      }
    )
    (var-set next-emergency-id (+ emergency-id u1))
    (ok emergency-id)
  )
)

;; Emergency response
(define-public (respond-to-emergency (emergency-id uint))
  (let (
    (emergency (unwrap! (map-get? emergency-incidents { emergency-id: emergency-id }) ERR_NOT_FOUND))
    (responder (unwrap! (map-get? emergency-responders tx-sender) ERR_UNAUTHORIZED))
  )
    (asserts! (get active responder) ERR_UNAUTHORIZED)
    (asserts! (is-none (get current-emergency responder)) ERR_ALREADY_RESPONDED)
    (asserts! (is-eq (get status emergency) STATUS_REPORTED) ERR_ALREADY_RESPONDED)

    ;; Update emergency
    (map-set emergency-incidents
      { emergency-id: emergency-id }
      (merge emergency {
        status: STATUS_DISPATCHED,
        response-time: block-height,
        responder: (some tx-sender)
      })
    )

    ;; Update responder
    (map-set emergency-responders
      tx-sender
      (merge responder {
        current-emergency: (some emergency-id),
        total-responses: (+ (get total-responses responder) u1)
      })
    )

    (ok true)
  )
)

(define-public (update-emergency-status (emergency-id uint) (new-status uint))
  (let ((emergency (unwrap! (map-get? emergency-incidents { emergency-id: emergency-id }) ERR_NOT_FOUND)))
    (asserts! (is-eq (some tx-sender) (get responder emergency)) ERR_UNAUTHORIZED)
    (asserts! (and (>= new-status STATUS_REPORTED) (<= new-status STATUS_RESOLVED)) ERR_INVALID_EMERGENCY)

    (map-set emergency-incidents
      { emergency-id: emergency-id }
      (merge emergency {
        status: new-status,
        resolved-time: (if (is-eq new-status STATUS_RESOLVED) block-height (get resolved-time emergency))
      })
    )

    ;; Clear responder assignment if resolved
    (if (is-eq new-status STATUS_RESOLVED)
      (let ((responder (unwrap! (map-get? emergency-responders tx-sender) ERR_NOT_FOUND)))
        (map-set emergency-responders
          tx-sender
          (merge responder { current-emergency: none })
        )
        (ok true)
      )
      (ok true)
    )
  )
)

;; Traffic diversion management
(define-public (create-traffic-diversion
  (emergency-id uint)
  (affected-zone uint)
  (diversion-route (string-ascii 200))
)
  (let ((diversion-id (var-get next-diversion-id)))
    (asserts! (is-some (map-get? emergency-incidents { emergency-id: emergency-id })) ERR_NOT_FOUND)
    (map-set traffic-diversions
      { diversion-id: diversion-id }
      {
        emergency-id: emergency-id,
        affected-zone: affected-zone,
        diversion-route: diversion-route,
        active: true,
        created-time: block-height
      }
    )
    (var-set next-diversion-id (+ diversion-id u1))
    (ok diversion-id)
  )
)

;; Read-only functions
(define-read-only (get-emergency (emergency-id uint))
  (map-get? emergency-incidents { emergency-id: emergency-id })
)

(define-read-only (get-responder (responder principal))
  (map-get? emergency-responders responder)
)

(define-read-only (get-traffic-diversion (diversion-id uint))
  (map-get? traffic-diversions { diversion-id: diversion-id })
)

(define-read-only (get-emergency-count)
  (- (var-get next-emergency-id) u1)
)

(define-read-only (is-active-responder (responder principal))
  (match (map-get? emergency-responders responder)
    responder-data (get active responder-data)
    false
  )
)
