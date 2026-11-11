"""Load the CSV files into SQLite, create the views and run every SQL query.

Uses only the Python standard library.

Usage:  python run_analysis.py
Output: portfolio.db, output/<query name>.csv, and the results printed on screen.
"""
import csv
import os
import re
import sqlite3

DB_PATH = "portfolio.db"
TABLES = ["customers", "contracts", "installments", "payments"]
QUERY_FILES = ["sql/03_analysis.sql", "sql/04_data_quality.sql"]
MAX_ROWS_ON_SCREEN = 15


def read_file(path):
    with open(path, encoding="utf-8") as f:
        return f.read()


def load_csv(conn, table):
    with open(f"data/{table}.csv", newline="", encoding="utf-8") as f:
        reader = csv.reader(f)
        header = next(reader)
        rows = [[value if value != "" else None for value in row] for row in reader]
    placeholders = ", ".join("?" for _ in header)
    conn.executemany(
        f"INSERT INTO {table} ({', '.join(header)}) VALUES ({placeholders})", rows)
    print(f"Loaded {len(rows):,} rows into {table}")


def split_queries(sql_text):
    """Return (name, sql) pairs for every block that starts with '-- name:'."""
    parts = re.split(r"^-- name:\s*(\S+)\s*$", sql_text, flags=re.MULTILINE)
    return [(parts[i], parts[i + 1].strip()) for i in range(1, len(parts), 2)]


def print_table(header, rows):
    shown = rows[:MAX_ROWS_ON_SCREEN]
    cells = [[("" if v is None else str(v)) for v in row] for row in shown]
    widths = [max(len(h), *(len(r[i]) for r in cells)) if cells else len(h)
              for i, h in enumerate(header)]
    print("  ".join(h.ljust(w) for h, w in zip(header, widths)))
    print("  ".join("-" * w for w in widths))
    for row in cells:
        print("  ".join(v.ljust(w) for v, w in zip(row, widths)))
    if len(rows) > len(shown):
        print(f"... {len(rows) - len(shown)} more rows in the CSV file")


def main():
    if os.path.exists(DB_PATH):
        os.remove(DB_PATH)
    os.makedirs("output", exist_ok=True)

    conn = sqlite3.connect(DB_PATH)
    conn.executescript(read_file("sql/01_schema.sql"))
    for table in TABLES:
        load_csv(conn, table)
    conn.executescript(read_file("sql/02_views.sql"))
    conn.commit()

    for path in QUERY_FILES:
        for name, sql in split_queries(read_file(path)):
            cursor = conn.execute(sql)
            header = [col[0] for col in cursor.description]
            rows = cursor.fetchall()
            with open(f"output/{name}.csv", "w", newline="", encoding="utf-8") as f:
                writer = csv.writer(f)
                writer.writerow(header)
                writer.writerows(rows)
            print(f"\n=== {name} ({len(rows)} rows) ===")
            print_table(header, rows)

    conn.close()


if __name__ == "__main__":
    main()
