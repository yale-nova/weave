To enable architecture emulation on Arm please enable QEMU plugins for docker by running. 
docker run --rm --privileged multiarch/qemu-user-static --reset -p yes

To create an azure container (direct mode only) with the created gramine-direct image, please run 
E.g. Image name = graminedirect.azurecr.io/spark-gramine-direct:latest

az container create \
  --resource-group graminedirect \
  --name weavec1 \
  --image graminetestacr.azurecr.io/spark-gramine:latest \
  --cpu 4 \
  --memory 16 \
  --registry-login-server graminetestacr.azurecr.io \
  --registry-username <username-from-`az acr credential show`> \
  --registry-password <password-from-`az acr credential show`> \
  --restart-policy Never \
  --os-type Linux


Please be aware that you need to create github_auth.env that will let you to fetch Weave private repositories.

### ⚠️ Azure CLI `az acr login` Warning (May 2025 Breaking Change)

As of Azure CLI version **2.73.0** (scheduled for release in **May 2025**), the behavior of `az acr login` will change:

- If `docker login` fails during `az acr login`, the command will now return a **non-zero exit code** (`1`).
- Previously, it could incorrectly return success (`0`), even if authentication failed.

**Action Required:**  
If you're using `az acr login` in scripts or automation, ensure you handle potential failures explicitly.

Example:
```bash
az acr login --name myregistry || { echo "ACR login failed"; exit 1; }


This ensures your workflows remain compatible with the new behavior. 
