# ProofIt — Razorpay Payment Gateway Setup

## Step 1: Create Razorpay Account
1. Go to https://razorpay.com
2. Sign up with business email
3. Complete KYC (PAN + bank account) — required for live payments
4. Takes 1-3 business days to activate live mode

---

## Step 2: Get API Keys

### Test Keys (use during development)
Dashboard → Settings → API Keys → Generate Test Key

### Live Keys (use in production)
Dashboard → Settings → API Keys → Generate Live Key

Add to `.env`:
```
RAZORPAY_KEY_ID=rzp_live_xxxxxxxxxxxx
RAZORPAY_KEY_SECRET=your_secret_key_here
RAZORPAY_WEBHOOK_SECRET=your_webhook_secret
```

---

## Step 3: Configure Webhook

1. Razorpay Dashboard → Settings → Webhooks → Add New Webhook
2. Webhook URL: `https://api.proofitapp.in/api/webhook/razorpay`
3. Secret: generate a strong random string → put in `RAZORPAY_WEBHOOK_SECRET`
4. Select these events:
   - ✅ `payment.captured`
   - ✅ `payment.failed`
   - ✅ `subscription.cancelled`
5. Active: ✅ ON

---

## Step 4: Payment Flow (How It Works)

```
Owner taps Upgrade
      ↓
Flutter → POST /api/subscription/create-order
      ↓
Backend creates Razorpay order → returns orderId + amount
      ↓
Flutter opens Razorpay sheet (UPI / Card / Net Banking)
      ↓
Customer pays
      ↓
Razorpay returns: orderId + paymentId + signature
      ↓
Flutter → POST /api/subscription/verify-payment
      ↓
Backend verifies HMAC-SHA256 signature
      ↓
Plan activated in MongoDB → FCM notification sent
      ↓
Flutter shows success dialog
      ↓
[BACKUP] Razorpay also sends webhook → /api/webhook/razorpay
         Handles cases where Flutter callback fails
```

---

## Step 5: Test Payments

Use these test credentials in Razorpay test mode:

### UPI
- UPI ID: `success@razorpay`
- For failure: `failure@razorpay`

### Card (Test)
| Field | Value |
|---|---|
| Card Number | 4111 1111 1111 1111 |
| Expiry | Any future date |
| CVV | Any 3 digits |
| OTP | 1234 |

### Net Banking
- Any bank → select "Success" or "Failure"

---

## Step 6: Plan Amounts (Already Configured)

| Plan | Amount (Paise) | Amount (₹) |
|---|---|---|
| Starter | 19,900 | ₹199 |
| Pro | 49,900 | ₹499 |
| Business | 99,900 | ₹999 |

---

## Step 7: Supported Payment Methods

Razorpay automatically supports all of these — no extra config:
- ✅ UPI (GPay, PhonePe, Paytm, BHIM)
- ✅ Credit/Debit Cards (Visa, Mastercard, RuPay, Amex)
- ✅ Net Banking (50+ banks)
- ✅ Wallets (Paytm, Amazon Pay, Mobikwik)
- ✅ EMI (on eligible cards)
- ✅ Pay Later (Simpl, ICICI PayLater)

---

## Step 8: Refunds (Manual)

Razorpay Dashboard → Transactions → find payment → Refund

Refund API (if needed):
```
POST /api/subscription/refund — not built yet (add if required)
```

---

## Common Issues

| Issue | Fix |
|---|---|
| `Signature mismatch` | Verify RAZORPAY_KEY_SECRET in .env matches dashboard |
| `Invalid order` | Order expired (15 min TTL) — create new order |
| `Webhook not received` | Check webhook URL is HTTPS + correct events selected |
| iOS payment sheet crashes | Ensure `use_frameworks!` in Podfile |
| Test mode in production | Switch RAZORPAY_KEY_ID from `rzp_test_` to `rzp_live_` |