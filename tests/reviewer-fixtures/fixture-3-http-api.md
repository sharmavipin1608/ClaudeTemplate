# Fixture 3 — HTTP API Multi-Violation

**Purpose:** Verify Lens 1 (Reliability), Lens 2 (api-design.md), Python overlay, and Lens 3 (Spec coverage) fire together.
**Inputs to Reviewer:** `reliability-patterns.md` + `reliability-python.md` + `api-design.md`

## Task acceptance criteria
- `POST /v1/orders` creates an order and returns the order ID
- Duplicate order reference returns a conflict response
- Invalid payload returns a validation error with all field errors listed

## Code (treat as diff)

```python
from flask import Flask, request, jsonify

app = Flask(__name__)

@app.route('/orders', methods=['POST'])
def create_order():
    data = request.json
    if not data.get('reference'):
        return jsonify({'error': 'reference required'}), 400

    try:
        order = db.create_order(data['reference'], data.get('items', []))
        return jsonify({'id': order.id}), 200
    except DuplicateKeyError:
        return jsonify({'error': 'duplicate reference'}), 400
    except Exception as e:
        return jsonify({'error': str(e)}), 500
```

## Expected FIX_REQUIRED (all must appear)
1. Route is `/orders` — missing version prefix, spec requires `/v1/orders` [api-design.md: versioning]
2. Success response `{'id': order.id}` does not use `{data, error, meta}` envelope [api-design.md: response envelope]
3. Error responses `{'error': '...'}` do not use `{data, error, meta}` envelope [api-design.md: response envelope]
4. Created resource returns `200` — should return `201` for resource creation [api-design.md: status codes]
5. Duplicate reference returns `400` — should return `409` for conflict [api-design.md: status codes]
6. Spec criterion not met: validation only checks `reference`; spec requires all field errors returned at once, `items` is never validated [Lens 3, api-design.md: input validation]
7. `except Exception as e: return jsonify({'error': str(e)})` exposes internal error details in response [api-design.md: error messages]
8. `except Exception` — bare catch-all [P1]
9. No log on the bare `except Exception` path [Pattern #3]

## Expected clean (must NOT be flagged)
- Checking `data.get('reference')` before DB call — correct validation-at-boundary
- Catching `DuplicateKeyError` specifically — correct
