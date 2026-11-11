"""Generate a synthetic equipment-financing portfolio as CSV files.

All data is fictional and randomly generated with a fixed seed, so every run
produces the same files. A small number of data quality problems are injected
on purpose so that the checks in sql/04_data_quality.sql have something to find.

Usage:  python generate_data.py
Output: data/customers.csv, data/contracts.csv, data/installments.csv,
        data/payments.csv
"""
import csv
import os
import random
from datetime import date, timedelta

SEED = 42
SNAPSHOT_DATE = date(2026, 10, 31)   # reporting date used by the analysis
N_CUSTOMERS = 300
N_CONTRACTS = 800

SEGMENTS = [("Agriculture", 0.60), ("Construction", 0.25), ("Landscaping", 0.15)]
STATES = ["SP", "MT", "PR", "RS", "GO", "MG", "MS"]
RATINGS = [("A", 0.35), ("B", 0.35), ("C", 0.20), ("D", 0.10)]
EQUIPMENT = {
    "Agriculture": ["Tractor", "Combine Harvester", "Sprayer", "Planter"],
    "Construction": ["Excavator", "Wheel Loader", "Backhoe"],
    "Landscaping": ["Compact Tractor", "Mower"],
}
# Risk assumptions per credit rating
DEFAULT_PROB = {"A": 0.02, "B": 0.05, "C": 0.12, "D": 0.25}   # contract stops paying
LATE_PROB = {"A": 0.05, "B": 0.10, "C": 0.20, "D": 0.30}      # installment paid late
ANNUAL_RATE = {"A": (0.09, 0.11), "B": (0.11, 0.13), "C": (0.13, 0.16), "D": (0.16, 0.19)}


def weighted(options):
    values = [v for v, _ in options]
    weights = [w for _, w in options]
    return random.choices(values, weights=weights, k=1)[0]


def add_months(d, months):
    month_index = d.month - 1 + months
    year = d.year + month_index // 12
    month = month_index % 12 + 1
    day = min(d.day, 28)
    return date(year, month, day)


def random_date(start, end):
    return start + timedelta(days=random.randint(0, (end - start).days))


def write_csv(path, header, rows):
    with open(path, "w", newline="", encoding="utf-8") as f:
        writer = csv.writer(f)
        writer.writerow(header)
        writer.writerows(rows)
    print(f"{path}: {len(rows):,} rows")


def main():
    random.seed(SEED)
    os.makedirs("data", exist_ok=True)

    # ---------------------------------------------------------------- customers
    customers = []
    for cid in range(1, N_CUSTOMERS + 1):
        customers.append({
            "customer_id": cid,
            "segment": weighted(SEGMENTS),
            "state": random.choice(STATES),
            "credit_rating": weighted(RATINGS),
            "customer_since": random_date(date(2015, 1, 1), date(2022, 12, 31)),
        })

    # ------------------------------------------- contracts, installments, payments
    contracts, installments, payments = [], [], []
    full_payment_idx = []          # indexes of ordinary full payments (for DQ injection)
    origination_by_installment = {}
    installment_id = 0
    payment_id = 0

    for contract_id in range(1001, 1001 + N_CONTRACTS):
        cust = random.choice(customers)
        rating = cust["credit_rating"]
        origination = random_date(date(2023, 1, 1), date(2026, 6, 30))
        term = random.choice([12, 24, 36, 48, 60])
        financed = round(min(max(random.lognormvariate(12.2, 0.6), 50_000), 900_000), 2)
        rate = round(random.uniform(*ANNUAL_RATE[rating]), 4)
        monthly_rate = rate / 12
        installment_amount = round(
            financed * monthly_rate / (1 - (1 + monthly_rate) ** -term), 2)

        defaults = random.random() < DEFAULT_PROB[rating]
        default_from = random.randint(3, term) if defaults else None

        last_due = add_months(origination, term)
        status = "Closed" if (last_due < SNAPSHOT_DATE and not defaults) else "Active"
        contracts.append([
            contract_id, cust["customer_id"],
            "Installment Loan" if random.random() < 0.70 else "Lease",
            random.choice(EQUIPMENT[cust["segment"]]),
            origination.isoformat(), term, financed, rate, status,
        ])

        for n in range(1, term + 1):
            installment_id += 1
            due = add_months(origination, n)
            installments.append(
                [installment_id, contract_id, n, due.isoformat(), installment_amount])
            origination_by_installment[installment_id] = origination

            if due > SNAPSHOT_DATE:
                continue                      # not due yet, nothing paid
            if default_from is not None and n >= default_from:
                continue                      # contract stopped paying

            if random.random() < LATE_PROB[rating]:
                days_late = max(1, min(int(random.expovariate(1 / 15)), 120))
            else:
                days_late = -random.randint(0, 3)   # on time or a few days early
            paid_on = due + timedelta(days=days_late)
            if paid_on > SNAPSHOT_DATE:
                continue                      # still open at the reporting date

            if random.random() < 0.03:        # partial payment
                first = round(installment_amount * random.uniform(0.5, 0.9), 2)
                payment_id += 1
                payments.append([payment_id, installment_id, paid_on.isoformat(), first])
                second_on = paid_on + timedelta(days=random.randint(10, 40))
                if random.random() < 0.95 and second_on <= SNAPSHOT_DATE:
                    payment_id += 1
                    payments.append([payment_id, installment_id, second_on.isoformat(),
                                     round(installment_amount - first, 2)])
            else:
                payment_id += 1
                payments.append(
                    [payment_id, installment_id, paid_on.isoformat(), installment_amount])
                full_payment_idx.append(len(payments) - 1)

    # ------------------------------------------------ injected data quality issues
    picked = random.sample(full_payment_idx, 30)
    dup_idx, over_idx, null_idx, early_idx = (
        picked[:15], picked[15:23], picked[23:27], picked[27:30])

    for i in over_idx:                         # overpayments (10% above amount due)
        payments[i][3] = round(payments[i][3] * 1.10, 2)
    for i in null_idx:                         # missing amount
        payments[i][3] = ""
    for i in early_idx:                        # payment dated before the contract
        origination = origination_by_installment[payments[i][1]]
        payments[i][2] = (origination - timedelta(days=10)).isoformat()
    for i in dup_idx:                          # duplicated payment records
        payment_id += 1
        payments.append([payment_id] + payments[i][1:])
    for k in range(5):                         # payments without an installment
        payment_id += 1
        payments.append([payment_id, 9_000_001 + k,
                         random_date(date(2025, 1, 1), SNAPSHOT_DATE).isoformat(),
                         round(random.uniform(2_000, 15_000), 2)])

    # contracts missing their final installment (count no longer matches the term)
    last_installment = {}
    for row in installments:
        last_installment[row[1]] = row
    candidates = [r for r in last_installment.values() if r[3] > SNAPSHOT_DATE.isoformat()]
    to_remove = {r[0] for r in random.sample(candidates, 3)}
    installments = [r for r in installments if r[0] not in to_remove]

    random.shuffle(payments)                   # no meaningful physical order

    # --------------------------------------------------------------------- output
    write_csv("data/customers.csv",
              ["customer_id", "segment", "state", "credit_rating", "customer_since"],
              [[c["customer_id"], c["segment"], c["state"], c["credit_rating"],
                c["customer_since"].isoformat()] for c in customers])
    write_csv("data/contracts.csv",
              ["contract_id", "customer_id", "product_type", "equipment_type",
               "origination_date", "term_months", "financed_amount",
               "annual_interest_rate", "status"], contracts)
    write_csv("data/installments.csv",
              ["installment_id", "contract_id", "installment_number", "due_date",
               "amount_due"], installments)
    write_csv("data/payments.csv",
              ["payment_id", "installment_id", "payment_date", "amount_paid"], payments)


if __name__ == "__main__":
    main()
