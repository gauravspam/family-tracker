#!/usr/bin/env python3
"""Simulate device moving home→garage→home with smooth GPS trail."""
import time, math, random, subprocess, sys

DEVICE_ID = "M5RXTgEIhHyv3q1iNgsYdg"  # Device 2 — Dad
TRACCAR_INGEST = "http://localhost:5055"
HOME = (19.1237834, 72.9928145)
GARAGE = (19.0861106, 72.9988556)
STEPS = 85
DELAY = 2.5

def send(step, lat, lon, batt, speed, bearing, activity):
    url = (f"{TRACCAR_INGEST}/?id={DEVICE_ID}"
           f"&lat={lat:.6f}&lon={lon:.6f}&timestamp={int(time.time())}"
           f"&hdop={random.uniform(3,8):.1f}&altitude={random.uniform(-39,-38):.1f}"
           f"&speed={speed:.2f}&bearing={bearing:.1f}&batt={batt}&activity={activity}")
    r = subprocess.run(["curl", "-s", "-o", "/dev/null", "-w", "%{http_code}", url],
                       timeout=10, capture_output=True)
    code = r.stdout.decode().strip()
    ok = code == "200"
    print(f"[{step:3d}] lat={lat:.6f} lon={lon:.6f} spd={speed:.2f} act={activity} batt={batt}% HTTP={code}{' OK' if ok else ' FAIL'}")
    return ok

def simulate(start, end, offset=0, batt_start=80):
    for i in range(STEPS):
        t = (i+1)/STEPS
        st = t*t*(3-2*t)
        j = 0.00003*math.sin(i*0.4)
        lat = start[0]+(end[0]-start[0])*st + j
        lon = start[1]+(end[1]-start[1])*st + j*0.5
        speed = 2.0*math.sin(t*math.pi)
        dlon = math.radians(end[1]-lon)
        x = math.sin(dlon)*math.cos(math.radians(end[0]))
        y = (math.cos(math.radians(lat))*math.sin(math.radians(end[0]))
             - math.sin(math.radians(lat))*math.cos(math.radians(end[0]))*math.cos(dlon))
        bear = (math.degrees(math.atan2(x,y))+360)%360
        batt = max(batt_start - (offset+i)*0.05, 10)
        act = "walking" if 5 < i < STEPS-5 else "still"
        if not send(offset+i+1, lat, lon, int(batt), speed, bear, act):
            return False
        time.sleep(DELAY)
    return True

print(f"Home→Garage→Home ({STEPS*2} steps, ~{STEPS*2*DELAY/60:.0f} min)")
print("Starting in 3 seconds...")
time.sleep(3)
print("\n--- Home → Garage ---")
if simulate(HOME, GARAGE, 0):
    print("\n--- Pause at Garage ---")
    for i in range(5):
        send(STEPS*2+i+1, GARAGE[0], GARAGE[1], int(60-i*2), 0, 0, "still")
        time.sleep(DELAY)
    print("\n--- Garage → Home ---")
    simulate(GARAGE, HOME, STEPS+5, 50)
print("\n✅ Done")
