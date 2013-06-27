#!/usr/bin/env chicken-scheme

;; [[file:~/prg/scm/aima/aima.org::*6.1][6\.1:1]]

(use debug
     define-record-and-printer
     matchable
     srfi-1
     srfi-69
     test)

(define-record-and-printer unassigned)
(define unassigned (make-unassigned))
(define assigned? (complement unassigned?))

(define-record-and-printer failure)
(define failure (make-failure))

(define-record-and-printer csp
  domains
  constraints
  neighbors)

(define (csp-copy csp)
  (make-csp (hash-table-copy (csp-domains csp))
            (hash-table-copy (csp-constraints csp))
            (hash-table-copy (csp-neighbors csp))))

;;; Dispense with this and do equality on the number of keys!
(define (make-assignment csp)
  (alist->hash-table
   (map (lambda (variable) (cons variable unassigned))
        (hash-table-keys (csp-domains csp)))))

(define (backtracking-search csp)
  (backtrack (make-assignment csp) csp))

(define (complete? assignment)
  (hash-table-fold
   assignment
   (lambda (variable value complete?)
     (and (assigned? value) complete?))
   #t))

;;; Too bad this is linear across variables, right? Optimize later.
;;; 
;;; Need the CSP, at some point, to do the degree heuristic.
(define (select-unassigned-variable assignment)
  ;; We can assume there is at least one unassigned variable.
  (car (find (compose unassigned? cdr) (hash-table->alist assignment))))

;;; Need assignment, at some point, to do least-constraining-value.
(define (order-domain-values variable csp)
  (hash-table-ref (csp-domains csp) variable))

;;; Find the assigned neighbors of the variable; does the value
;;; satisfy each constraint?
;;;
;;; What if the variable is already assigned something else? Seems
;;; like a pathological case.
;;;
;;; Should we check here if we've already assigned something?
(define (consistent? variable value assignment csp)
  ;; (debug variable
  ;;        value
  ;;        (hash-table-ref assignment variable)
  ;;        (or (unassigned? (hash-table-ref assignment variable))
  ;;            (eq? value (hash-table-ref assignment variable))))
  (let* ((neighbors (hash-table-ref (csp-neighbors csp) variable))
         (assigned-neighbors (filter (lambda (neighbor) (assigned? (hash-table-ref assignment neighbor)))
                                     neighbors)))
    (every values (map (lambda (neighbor) ((hash-table-ref (csp-constraints csp) (cons variable neighbor))
                                      value
                                      (hash-table-ref assignment neighbor)))
                       assigned-neighbors))))

(define (inference csp variable value)
  (make-hash-table))

;;; This version just does the first solution; need to enumerate them.
(define (backtrack assignment csp)
  (if (complete? assignment)
      assignment
      ;; Asks the CSP, since it might have information about the
      ;; constraints; e.g. degree heuristic. Don't we need the current
      ;; assignment, though, too?
      ;;
      ;; Oh, but the CSP has information about the domains
      ;; corresponding to variables; which change according to the
      ;; assignment.
      ;;
      ;; This is why, for instance, inference is called on the CSP.
      ;;
      ;; As we make assignments, therefore, we should also constrain
      ;; the domain contained in the CSP.
      ;;
      ;; In fact, as regards the CSP: hash-table containing variables,
      ;; domains (which are constrained by inference); and a list of
      ;; constraints: a table indexed by a tuple of variables pointing
      ;; to a either 1) possible tuples that satisfy constraint; 2)
      ;; abstract relation specifying whether e.g. X_1, X_2 satisfy
      ;; the constraint and enumurating the members of the relation.
      (let ((variable (select-unassigned-variable assignment)))
        (let iter ((values (order-domain-values variable csp)))
          (if (null? values)
              failure
              (let ((value (car values))
                    (csp (csp-copy csp))
                    (assignment (hash-table-copy assignment)))
                ;; Do we have to address constraints at this point? Yes.
                (if (consistent? variable value assignment csp)
                    (begin
                      ;; Copy at this point?
                      (hash-table-set! assignment variable value)
                      ;; This might actually modify the domains in the CSP;
                      ;; better copy before we get here?
                      (let ((inferences (inference csp variable value)))
                        (if (failure? inferences)
                            (iter (cdr values))
                            (begin
                              ;; When duplicate, take inferences; the only
                              ;; values we should be overriding, however, are
                              ;; unassigned.
                              (hash-table-merge! inferences assignment)
                              (let ((result (backtrack assignment csp)))
                                (if (failure? result)
                                    (iter (cdr values))
                                    result))))))
                    (iter (cdr values)))))))))

(define (backtracking-enumeration csp)
  (let ((enumeration (make-parameter '())))
    (backtrack-enumerate enumeration (make-assignment csp) csp)
    (enumeration)))

;;; This version just does the first solution; need to enumerate them.
(define (backtrack-enumerate enumeration assignment csp)
  ;; No inference.
  (let iter-variables ((variables (hash-table-keys csp)))
    (unless (null? variables)
      (let ((variable (car variables)))
        (let iter-values ((values (hash-table-ref (csp-domain csp) variable)))
          (if (null? values)
              (iter-variables (cdr variables))
              (let ((value (car values)))
                (if (consistent? variable value assignment csp)
                    (begin
                      (hash-table-set! assignment variable value)
                      (let ((inference (inference csp variable value)))
                        (if (failure? inference)
                            (iter-values (cdr values))
                            (begin
                              (hash-table-merge! inferences assignment)
                              (let ((result (backtrack-enumerate enumeration assignment csp)))
                                (if (failure? result)
                                    (iter-variables (cdr variables))
                                    result)))))))))))))
  ;; (debug (hash-table->alist assignment))
  ;; (if (complete? assignment)
  ;;     (enumeration (cons assignment (enumeration)))
  ;;     (let ((variable (select-unassigned-variable assignment)))
  ;;       (let iter ((values (order-domain-values variable csp)))
  ;;         (if (null? values)
  ;;             failure
  ;;             (let ((value (car values))
  ;;                   (csp (csp-copy csp))
  ;;                   (assignment (hash-table-copy assignment)))
  ;;               ;; Do we have to address constraints at this point? Yes.
  ;;               (if (consistent? variable value assignment csp)
  ;;                   (begin
  ;;                     ;; Copy at this point?
  ;;                     (hash-table-set! assignment variable value)
  ;;                     ;; This might actually modify the domains in the CSP;
  ;;                     ;; better copy before we get here?
  ;;                     (let ((inferences (inference csp variable value)))
  ;;                       (if (failure? inferences)
  ;;                           (iter (cdr values))
  ;;                           (begin
  ;;                             ;; When duplicate, take inferences; the only
  ;;                             ;; values we should be overriding, however, are
  ;;                             ;; unassigned.
  ;;                             (hash-table-merge! inferences assignment)
  ;;                             (let ((result (backtrack-enumerate enumeration assignment csp)))
  ;;                               (if (failure? result)
  ;;                                   (iter (cdr values))
  ;;                                   result))))))
  ;;                   (iter (cdr values))))))))
  )

;;; Do we need to copy the thing? We're constantly destroying the CSP.
(define (ac-3 csp)
  (let ((queue (list->queue (hash-table-keys (csp-constraints csp)))))
    (let iter ()
      (if (queue-empty? queue)
          #t
          (match (queue-remove! queue)
            ((x . y)
             (if (revise csp x y)
                 ;; How does this work for e.g. infinite domains?
                 (if (zero? (length (hash-table-ref (csp-domains csp) x)))
                     #f
                     (begin
                       (for-each (lambda (neighbor)
                                   (queue-add! queue (cons neighbor x)))
                         (delete y (hash-table-ref (csp-neighbors csp) x)))
                       (iter)))
                 (iter))))))))

(define (revise csp x y)
  (let ((y-domain (hash-table-ref (csp-domains csp) y))
        (constraint (hash-table-ref (csp-constraints csp) (cons x y))))
    (let iter ((revised #f)
               (x-domain (hash-table-ref (csp-domains csp) x)))
      ;; (debug revised x-domain)
      ;; How does this work for infinite domains?
      (if (null? x-domain)
          revised
          (let ((x-value (car x-domain)))
            (if (any values (map (lambda (y-value) (constraint x-value y-value)) y-domain))
                (iter revised (cdr x-domain))
                (begin
                  (hash-table-update!
                   (csp-domains csp)
                   x
                   (lambda (x-domain)
                     (delete x-value x-domain)))
                  (iter #t (cdr x-domain)))))))))

(define neq? (complement eq?))

(define arc-consistent-coloring
  (make-csp
   ;; Domain can also be lambdas?
   (alist->hash-table '((a . (white black))
                        (b . (white black))))
   (alist->hash-table `(((a . b) . ,neq?)
                        ((b . a) . ,neq?)))
   (alist->hash-table '((a b)
                        (b a)))))

(define arc-inconsistent-coloring
  (make-csp
   ;; Domain can also be lambdas?
   (alist->hash-table '((a . (white))
                        (b . (white))))
   (alist->hash-table `(((a . b) . ,neq?)
                        ((b . a) . ,neq?)))
   (alist->hash-table '((a b)
                        (b a)))))

(define 3-colors '(red green blue))

;;; Could find a mechanism for automatically creating these things;
;;; indeed, will have to randomly.
(define 3-color-australia
  (make-csp
   (alist->hash-table `((wa . ,3-colors)
                        (nt . ,3-colors)
                        (sa . ,3-colors)
                        (q . ,3-colors)
                        (nsw . ,3-colors)
                        (v . ,3-colors)
                        (t . ,3-colors)))
   (alist->hash-table `(((wa . nt) . ,neq?)
                        ((nt . wa) . ,neq?)
                        ((wa . sa) . ,neq?)
                        ((sa . wa) . ,neq?)
                        ((nt . sa) . ,neq?)
                        ((sa . nt) . ,neq?)
                        ((nt . q) . ,neq?)
                        ((q . nt) . ,neq?)
                        ((sa . q) . ,neq?)
                        ((q . sa) . ,neq?)
                        ((nsw . q) . ,neq?)
                        ((q . nsw) . ,neq?)
                        ((nsw . v) . ,neq?)
                        ((v . nsw) . ,neq?)
                        ((sa . nsw) . ,neq?)
                        ((nsw . sa) . ,neq?)
                        ((sa . v) . ,neq?)
                        ((v . sa) . ,neq?)))
   (alist->hash-table '((wa nt sa)
                        (nt wa sa)
                        (sa wa nt q nsw v)
                        (q nt sa nsw)
                        (nsw q sa v)
                        (v nsw sa)
                        (t)))))

;; (test-assert (ac-3 arc-consistent-coloring))

;; (test-assert (not (ac-3 arc-inconsistent-coloring)))

;; (test '((b . white) (a . black))
;;       (hash-table->alist (backtracking-search arc-consistent-coloring)))

;; (test-assert (failure? (backtracking-search arc-inconsistent-coloring)))

;; (test '((wa . red)
;;         (v . red)
;;         (t . red)
;;         (q . red)
;;         (sa . green)
;;         (nt . blue)
;;         (nsw . blue))
;;       (hash-table->alist (backtracking-search 3-color-australia)))

(debug (map hash-table->alist (backtracking-enumeration 3-color-australia)))

;; 6\.1:1 ends here