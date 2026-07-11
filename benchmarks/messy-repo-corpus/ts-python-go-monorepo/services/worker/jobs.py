import os

def run_job():
    if os.environ.get("ENABLE_WORKER"):
        return "ran"
    return "skipped"
