# CompareNukki local runtime environment.
# From the repository root:  source scripts/dev_env.sh
# Then run Flutter from the same shell so the app inherits these values.

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")/.." && pwd)"

export COMPARENUKKI_PYTHON="$ROOT/.venv/bin/python3"
export COMPARENUKKI_BACKEND_DIR="$ROOT/backend"
export NUKKI_MODEL_DIR="${HOME}/.u2net"
export U2NET_MODEL_PATH="${NUKKI_MODEL_DIR}/u2net.onnx"
export ISNET_MODEL_PATH="${NUKKI_MODEL_DIR}/isnet-general-use.onnx"
export BIREFNET_MODEL_PATH="${NUKKI_MODEL_DIR}/birefnet-general.onnx"
export RMBG_MODEL_PATH="${NUKKI_MODEL_DIR}/bria_rmbg14.onnx"
export INSPYRENET_CHECKPOINT="${HOME}/.transparent-background/ckpt_base.pth"
export MOBILESAM_CHECKPOINT="${NUKKI_MODEL_DIR}/mobile_sam.pt"
export NUKKI_ORT_THREADS="${NUKKI_ORT_THREADS:-4}"
export NUKKI_MAX_RESIDENT_MODELS="${NUKKI_MAX_RESIDENT_MODELS:-2}"
export NUKKI_LOG_LEVEL="${NUKKI_LOG_LEVEL:-WARNING}"

# Leave NUKKI_ORT_PROVIDER, INSPYRENET_DEVICE, and MOBILESAM_DEVICE unset
# so Apple Silicon can use CoreML / MPS. Override explicitly if needed:
#   export NUKKI_ORT_PROVIDER=CPUExecutionProvider
#   export INSPYRENET_DEVICE=cpu
#   export MOBILESAM_DEVICE=cpu
