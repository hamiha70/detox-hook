import os
print("Testing DEPLOYMENT_KEY:", os.getenv("DEPLOYMENT_KEY", "NOT_SET")[:10])
