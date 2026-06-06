# Fixture 2 — Java Multi-Violation

**Purpose:** Verify Lens 1 (Reliability), Java overlay, and Lens 3 (Spec coverage) all fire.
**Inputs to Reviewer:** `reliability-patterns.md` + `reliability-java.md`

## Task acceptance criteria
- `PaymentProcessor.charge(customerId, amount)` returns a `PaymentResult` with status and transaction ID
- Insufficient funds must be distinguishable from network errors at the call site
- All payment attempts must be logged

## Code (treat as diff)

```java
public class PaymentProcessor {
    private final PaymentGateway gateway;
    private final AuditLog audit;

    public PaymentResult charge(String customerId, double amount) {
        try {
            GatewayResponse resp = gateway.submit(customerId, amount);
            audit.record(customerId, amount, "success");
            return new PaymentResult(resp.getTxId(), null);
        } catch (Exception e) {
            return new PaymentResult(null, null);
        }
    }

    public void refund(String txId) {
        try {
            gateway.reverse(txId);
        } catch (InsufficientFundsException e) {
        } catch (Exception e) {
            throw new RuntimeException("refund failed");
        }
    }

    private PaymentResult retryCharge(String customerId, double amount, int maxAttempts) {
        PaymentResult result = null;
        for (int i = 0; i < maxAttempts; i++) {
            result = charge(customerId, amount);
            if (result.isSuccess()) return result;
        }
        return result;
    }

    public String getStatus(String txId) {
        try {
            return gateway.lookup(txId).getStatus();
        } catch (Exception e) {
            return null;
        }
    }
}
```

## Expected FIX_REQUIRED (all must appear)
1. `charge`: `catch (Exception e)` swallows `InsufficientFundsException` and network errors identically — violates spec requirement that callers can distinguish them [Pattern #2, J1]
2. `charge`: `new PaymentResult(null, null)` returned for all failures — indistinguishable at call site [Pattern #1]
3. `charge`: exception caught with no log — failures are invisible to operators [Pattern #3, Pattern #4]
4. `refund`: `catch (InsufficientFundsException e) {}` — empty catch block [J2]
5. `refund`: `throw new RuntimeException("refund failed")` — inside catch block, no root cause attached [J6]
6. `retryCharge`: `maxAttempts` is caller-controlled with no upper bound enforced internally [Pattern #5]
7. `retryCharge`: delegates to `charge()` which swallows all exceptions — retries permanent failures [Pattern #5]
8. `retryCharge`: no log per retry attempt [Pattern #5]
9. `getStatus`: returns `null` as error signal — no `@Nullable` annotation, no `Optional<T>` [J5, Pattern #1]
10. Spec criterion not met: all payment attempts must be logged — `charge` only logs success, failures have no audit record [Lens 3]

## Expected clean (must NOT be flagged)
- Constructor injection of `gateway` and `audit` — correct design
- `retryCharge` being private — acceptable
