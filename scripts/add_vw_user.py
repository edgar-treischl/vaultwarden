# add_vw_user.py
import sqlite3
import bcrypt
import uuid
import datetime
import os

db_path = "/data/db.sqlite3"
email = os.environ["EMAIL"]
password = os.environ["PASSWORD"]

# Generate bcrypt hash
pw_hash = bcrypt.hashpw(password.encode(), bcrypt.gensalt()).decode()

# Connect to the database
conn = sqlite3.connect(db_path)
c = conn.cursor()

# Insert the new user
user_id = str(uuid.uuid4())
now = datetime.datetime.utcnow().isoformat()
c.execute(
    "INSERT INTO users (id, email, password, created_at, updated_at) VALUES (?, ?, ?, ?, ?)",
    (user_id, email, pw_hash, now, now)
)
conn.commit()
conn.close()

# Append to CSV for documentation
doc_file = "/data/vaultwarden_users.csv"
with open(doc_file, "a") as f:
    f.write(f"{email},{password},{user_id},{now}\n")

print(f"User {email} added successfully with ID {user_id}")