WINDOW_SECONDS = 60          # rolling window size for feature extraction
MIN_EVENTS_FOR_FEATURES = 3  # minimum telemetry points before computing features
HARSH_BRAKE_THRESHOLD_KMH = 15   # speed drop within one event to count as harsh braking
MAX_BUFFER_EVENTS = 60       # safety cap per session (1 event/sec worst case for 60s)

# Volatility multiplier tuning — driving behavior derived purely from the stream
VOLATILITY_WEIGHT_PER_HARSH_EVENT = 0.04   # +4% risk per harsh braking event in window
VOLATILITY_MULTIPLIER_CAP = 1.35            # never let behavior alone push risk past x1.35
