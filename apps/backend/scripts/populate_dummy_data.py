import requests
import json
from datetime import datetime, timedelta
import random

API_BASE_URL = "https://babyai-production-723a.up.railway.app"
TOKEN = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJleHAiOjE3NzQxNzQ4MjYsImlhdCI6MTc3MTU4MjgyNiwibmFtZSI6IlFBIFJlbW90ZSBUZXN0ZXIiLCJwcm92aWRlciI6Imdvb2dsZSIsInN1YiI6ImQ0YmI4NzI2LWUwMjUtNGZkYS1hN2IwLThjNjQ2MmIyODVhYyJ9.OI94tOG_EPw-Ia2MqX0Fy2sMkvdoCnBThI7xN4uefIk"

HEADERS = {
    "Authorization": f"Bearer {TOKEN}",
    "Content-Type": "application/json"
}

def get_baby_id():
    resp = requests.get(f"{API_BASE_URL}/api/v1/babies/profile", headers=HEADERS)
    if resp.status_code == 200:
        return resp.json().get("id")
    else:
        print(f"Failed to get baby ID: {resp.status_code} {resp.text}")
        return None

def create_event(baby_id, event_type, start_time, end_time=None, value=None):
    payload = {
        "baby_id": baby_id,
        "type": event_type,
        "start_time": start_time.isoformat() + "Z",
        "value": value or {}
    }
    if end_time:
        payload["end_time"] = end_time.isoformat() + "Z"
    
    resp = requests.post(f"{API_BASE_URL}/api/v1/events/manual", headers=HEADERS, json=payload)
    if resp.status_code == 200:
        print(f"Created {event_type} at {start_time}")
    else:
        print(f"Failed to create {event_type}: {resp.status_code} {resp.text}")

def populate():
    baby_id = get_baby_id()
    if not baby_id:
        return

    start_date = datetime(2026, 2, 2)
    end_date = datetime(2026, 2, 16)
    
    current_date = start_date
    while current_date <= end_date:
        print(f"Populating for {current_date.date()}...")
        
        # 1. Day Sleep (Naps) - 2-3 per day
        # Typically 10am, 2pm, 5pm
        nap_times = [
            (10, 0, 90), # 10:00 for 90 min
            (14, 30, 60), # 14:30 for 60 min
            (17, 0, 40)   # 17:00 for 40 min
        ]
        for h, m, dur in nap_times:
            # Add some randomness
            actual_h = h
            actual_m = m + random.randint(-15, 15)
            s_time = current_date.replace(hour=actual_h, minute=actual_m)
            e_time = s_time + timedelta(minutes=dur + random.randint(-10, 20))
            create_event(baby_id, "SLEEP", s_time, e_time, {"sleep_type": "nap"})

        # 2. Night Sleep
        # 20:00 to 07:00 next day
        s_time = current_date.replace(hour=20, minute=random.randint(0, 30))
        e_time = (current_date + timedelta(days=1)).replace(hour=7, minute=random.randint(0, 30))
        create_event(baby_id, "SLEEP", s_time, e_time, {"sleep_type": "night"})

        # 3. Formula - 5-6 times per day
        # 07:00, 11:00, 15:00, 19:00, 23:00
        feed_times = [7, 11, 15, 19, 23]
        for h in feed_times:
            s_time = current_date.replace(hour=h, minute=random.randint(0, 45))
            ml = random.randint(120, 200)
            create_event(baby_id, "FORMULA", s_time, value={"ml": ml})

        # 4. Diapers - 6-8 times per day
        for _ in range(random.randint(6, 8)):
            h = random.randint(0, 23)
            m = random.randint(0, 59)
            s_time = current_date.replace(hour=h, minute=m)
            is_poo = random.random() < 0.3
            if is_poo:
                create_event(baby_id, "POO", s_time, value={"count": 1})
            else:
                create_event(baby_id, "PEE", s_time, value={"count": 1})

        current_date += timedelta(days=1)

if __name__ == "__main__":
    populate()
