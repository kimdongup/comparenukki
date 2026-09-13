# CompareNukki 수행 방법

CompareNukki는 같은 입력 이미지를 최대 8개 배경 제거 엔진에 순차적으로 적용하고, 결과 이미지와 실행 시간·메모리 사용량을 비교하는 Flutter 데스크톱 앱입니다. 앱을 시작하거나 사진을 바꾸는 것만으로는 벤치마크가 실행되지 않습니다. 사용자가 **벤치마크 실행**을 눌렀을 때만 Python 워커가 시작됩니다.

## 1. 지원 범위

- 로컬 Python 벤치마크는 macOS, Windows, Linux 데스크톱에서만 동작하도록 구현되어 있습니다.
- 현재 저장소에는 macOS 데스크톱 러너가 포함되어 있으므로 별도 생성 작업 없이 바로 실행할 수 있는 대상은 macOS입니다.
- Windows/Linux에서 사용하려면 해당 운영체제에서 Flutter 데스크톱 도구 모음을 설치하고 플랫폼 러너를 먼저 생성해야 합니다.

  ```bash
  flutter create --platforms=windows,linux .
  ```

  필요한 현재 운영체제의 플랫폼만 지정해도 됩니다. 생성된 플랫폼 파일은 프로젝트에 추가되므로 실행 전에 변경 내역을 검토하십시오.
- Web, Android, iOS에서는 화면을 열 수 있어도 로컬 워커가 지원되지 않으며 **벤치마크 실행** 버튼이 비활성화됩니다.

## 2. 로컬 개발 환경 준비

### 필수 도구

- Python 3.11 권장
- Dart 3.5 이상을 포함하는 Flutter SDK
- 대상 데스크톱 빌드 도구
  - macOS: Xcode와 Xcode command-line tools
  - Windows: Visual Studio의 Desktop development with C++ 워크로드
  - Linux: Flutter가 요구하는 C++/GTK 개발 패키지

설치 상태는 저장소 루트에서 확인합니다.

```bash
python3 --version
flutter --version
flutter doctor -v
flutter devices
```

`flutter doctor -v`가 대상 데스크톱 툴체인의 오류를 보고하면 먼저 해당 항목을 해결하십시오.

### Python 가상환경과 기본 의존성

macOS/Linux:

```bash
python3 -m venv .venv
source .venv/bin/activate
python -m pip install --upgrade pip
python -m pip install -r backend/requirements.txt
```

Windows PowerShell:

```powershell
py -3.11 -m venv .venv
.\.venv\Scripts\Activate.ps1
python -m pip install --upgrade pip
python -m pip install -r backend/requirements.txt
```

기본 requirements에는 NumPy, OpenCV, psutil, ONNX Runtime, Pillow가 포함됩니다. 이 설치만으로 체크포인트가 필요 없는 `grabcut`, `watershed` 엔진을 실행할 수 있습니다. 네 ONNX 엔진은 ONNX Runtime도 사용하지만 아래의 호환 체크포인트를 별도로 준비해야 합니다.

### 선택형 Python 엔진

InSPyReNet과 MobileSAM은 장치별 PyTorch 설치 조건이 달라 기본 requirements에 포함되지 않습니다.

- InSPyReNet은 `transparent-background` 패키지의 `transparent_background.Remover` import와 `ckpt_base.pth`가 모두 필요합니다.
- MobileSAM은 `torch`, `mobile_sam.SamPredictor`/`sam_model_registry` import, `mobile_sam.pt`가 모두 필요합니다.

예를 들어 InSPyReNet 패키지는 활성화된 가상환경에 다음과 같이 설치할 수 있습니다.

```bash
python -m pip install transparent-background
```

PyTorch와 MobileSAM은 CPU/CUDA/MPS 및 운영체제에 맞는 배포판을 사용해 설치하십시오. 설치 후 앱이 사용할 **같은 Python 실행 파일**에서 import를 검증합니다.

```bash
python -c "from transparent_background import Remover; print('InSPyReNet import OK')"
python -c "import torch; from mobile_sam import SamPredictor; print('MobileSAM import OK')"
```

## 3. 모델 체크포인트 준비

앱은 모델을 자동으로 다운로드하지 않습니다. 각 구현의 입력 크기와 출력 형식에 맞는 체크포인트를 직접 준비해야 하며, 파일 이름만 바꾼 호환되지 않는 모델은 사용할 수 없습니다.

`NUKKI_MODEL_DIR`의 기본값은 `~/.u2net`입니다.

| 엔진 ID | 기본 체크포인트 경로 | 개별 경로 환경변수 |
| --- | --- | --- |
| `rembg_u2net` | `~/.u2net/u2net.onnx` | `U2NET_MODEL_PATH` |
| `isnet` | `~/.u2net/isnet-general-use.onnx` | `ISNET_MODEL_PATH` |
| `birefnet` | `~/.u2net/birefnet-general.onnx` | `BIREFNET_MODEL_PATH` |
| `rmbg` | `~/.u2net/bria_rmbg14.onnx` | `RMBG_MODEL_PATH` |
| `inspyrenet` | `~/.transparent-background/ckpt_base.pth` | `INSPYRENET_CHECKPOINT` |
| `mobilesam` | `~/.u2net/mobile_sam.pt` | `MOBILESAM_CHECKPOINT` |

`NUKKI_MODEL_DIR`은 네 ONNX 모델과 MobileSAM의 기본 경로에 적용됩니다. InSPyReNet에는 적용되지 않으므로 별도 위치를 쓸 때는 `INSPYRENET_CHECKPOINT`를 설정하는 것이 가장 명확합니다. InSPyReNet은 `TRANSPARENT_BACKGROUND_FILE_PATH`가 설정된 경우 그 경로 또는 그 파일의 상위 디렉터리에서도 `ckpt_base.pth`를 찾습니다.

모델을 한 디렉터리에 모아 사용하는 예:

```bash
export NUKKI_MODEL_DIR="/absolute/path/to/models"
export INSPYRENET_CHECKPOINT="/absolute/path/to/models/ckpt_base.pth"
```

Windows PowerShell:

```powershell
$env:NUKKI_MODEL_DIR = "C:\models\comparenukki"
$env:INSPYRENET_CHECKPOINT = "C:\models\comparenukki\ckpt_base.pth"
```

개별 환경변수를 설정하면 `NUKKI_MODEL_DIR`보다 우선합니다. 가능한 한 절대경로를 사용하십시오.

## 4. 실행 환경 설정

지원되는 환경변수는 다음과 같습니다.

| 환경변수 | 기본값 | 용도 |
| --- | --- | --- |
| `COMPARENUKKI_PYTHON` | 활성 가상환경, pyenv 또는 시스템 `python3`/`python` 탐색 | 워커를 실행할 Python 경로 |
| `COMPARENUKKI_BACKEND_DIR` | 현재 디렉터리의 `backend` 또는 앱 번들의 backend 탐색 | `engine_worker.py`가 있는 디렉터리 |
| `NUKKI_MODEL_DIR` | `~/.u2net` | ONNX 및 MobileSAM 모델 기본 디렉터리 |
| `NUKKI_ORT_PROVIDER` | `CPUExecutionProvider` | ONNX Runtime provider |
| `NUKKI_ORT_THREADS` | `4` | ONNX intra-op 스레드 수, 최소 1 |
| `NUKKI_MAX_RESIDENT_MODELS` | `2` | 워커에 유지할 무거운 모델 세션의 LRU 최대 개수. `0`이면 실행 후 즉시 해제 |
| `INSPYRENET_DEVICE` | `cpu` | InSPyReNet의 PyTorch 장치 |
| `MOBILESAM_DEVICE` | `cpu` | MobileSAM 장치. 예: `cpu`, `mps`, `cuda`, `cuda:0` |
| `NUKKI_LOG_LEVEL` | `WARNING` | Python 워커 stderr 로그 레벨 |

가상환경과 backend를 명시적으로 고정하는 것을 권장합니다.

macOS/Linux:

```bash
export COMPARENUKKI_PYTHON="$PWD/.venv/bin/python3"
export COMPARENUKKI_BACKEND_DIR="$PWD/backend"
```

Windows PowerShell:

```powershell
$env:COMPARENUKKI_PYTHON = (Resolve-Path ".venv\Scripts\python.exe").Path
$env:COMPARENUKKI_BACKEND_DIR = (Resolve-Path "backend").Path
```

환경변수는 `flutter run` 또는 배포 앱을 시작하는 프로세스에 상속되어야 합니다. macOS Finder에서 앱을 직접 열면 터미널의 `export` 값이 전달되지 않을 수 있으므로 개발 중에는 같은 터미널에서 실행하십시오.

기본 requirements의 `onnxruntime`은 CPU provider를 제공합니다. 다른 provider를 지정할 때는 해당 provider를 제공하는 ONNX Runtime 배포판과 장치 드라이버가 실제로 설치되어 있어야 합니다. 그렇지 않으면 관련 엔진은 `unavailable`이 됩니다.

## 5. Flutter 앱 실행

저장소 루트에서 Flutter 패키지를 준비한 뒤 대상 데스크톱으로 실행합니다.

```bash
flutter pub get
flutter run -d macos
```

플랫폼 러너를 준비한 Windows/Linux에서는 각각 다음을 사용합니다.

```bash
flutter run -d windows
flutter run -d linux
```

앱은 시작 시 첫 번째 샘플 이미지를 선택해 보여 주지만 Python 프로세스나 엔진은 실행하지 않습니다. 사진 선택 후에도 마찬가지입니다.

## 6. 앱에서 벤치마크 수행

1. **사진 추가** 영역에서 기본 샘플을 선택하거나 **내 이미지 추가**로 로컬 이미지 파일을 선택합니다.
2. 사진을 선택해도 연산은 시작되지 않습니다. 이전 결과가 있다면 새 입력과 혼동되지 않도록 초기화됩니다.
3. **벤치마크 실행**을 누릅니다. 같은 버튼은 상단 앱 바와 사진 추가 영역 아래쪽에 있습니다.
4. 최초 실행 시 백그라운드 Python 워커가 지연 시작됩니다. 8개 엔진이 registry 순서대로 실행되고 각 결과는 완료되는 즉시 화면에 추가됩니다.
5. 진행률과 현재 실행 중인 엔진은 사진 추가 영역, 앱 바, Compare 영역에 표시됩니다.
6. 전체 완료 후 상태 및 순위를 지표 비교 영역에서 확인합니다.

한 번 시작한 전체 요청의 기본 제한 시간은 3분입니다. 제한을 초과하거나 프로토콜/워커 오류가 발생하면 안전한 중단을 위해 워커 프로세스가 종료됩니다. 다음 실행에서는 새 워커를 시작합니다.

### 실행 취소

실행 중에는 **벤치마크 실행** 버튼이 **실행 취소**로 바뀝니다. 취소는 ONNX/PyTorch 네이티브 추론까지 확실히 멈추기 위해 Python 워커 자체를 종료합니다.

- 취소 전에 이미 수신한 결과는 화면에 남을 수 있습니다.
- 취소하면 워커의 warm 세션은 사라집니다.
- 새 사진을 선택하거나 새 벤치마크를 실행하면 기존 작업을 취소하고 이전 결과를 초기화합니다.

## 7. 세 화면 사용법

창 너비가 1180px 이상이면 **사진 추가 / Compare / 지표 비교**가 한 화면에 나란히 표시됩니다. 더 좁은 창에서는 하단 내비게이션으로 세 화면을 전환합니다. 좁은 화면의 초기 탭은 Compare입니다.

### 사진 추가

- 네 개의 내장 샘플 또는 로컬 이미지 파일을 선택합니다.
- 현재 선택 이미지와 해당 샘플의 비교 난점을 확인합니다.
- 벤치마크를 명시적으로 실행하거나 취소합니다.
- `실행 대기`, `작업 준비 중`, `백그라운드 측정 중`, `측정 완료`, `일부 엔진 측정 완료`, `실행 취소됨`, `실행 실패` 상태와 진행률을 확인합니다.

### Compare

- **동기화 그리드**: 엔진별 합성 결과, 실행 상태, 시간·메모리·provider를 카드 단위로 비교합니다.
- **2단 슬라이더**: 원본 또는 사용 가능한 두 엔진 결과를 선택하고 분할선을 움직여 동일 위치를 비교합니다.
- **알파 마스크**: 합성 이미지 대신 엔진이 생성한 회색조 알파 마스크를 검정 배경에서 비교합니다. 이 모드에서는 명암 해석이 바뀌지 않도록 배경이 고정됩니다.
- 합성 결과 모드에서는 **배경**을 격자, 블랙, 화이트, 크로마 그린으로 바꿔 투명도, 흰색 halo, 잘린 경계, 반투명 영역을 점검합니다.
- 엔진이 제공한 **코드** 버튼으로 실제 측정 경로와 같은 전처리·추론·후처리 설정을 사용하는 Python 재현 코드를 볼 수 있습니다. 입력 파일명과 출력 위치는 예시이므로 실행 환경에 맞게 바꾸십시오.

`unavailable` 또는 `failed` 결과는 출력 이미지 대신 원인을 담은 상태 카드로 표시됩니다.

### 지표 비교

- 성공했고 `rankable=true`인 결과가 순위 후보가 됩니다. 처리 시간과 추가 피크 메모리 순위는 각각 해당 지표가 유한한 후보만 사용하며, cold/비상주 결과와 warm 결과를 서로 다른 순위로 표시합니다.
- 성공했지만 `rankable=false`인 결과와 `unavailable`, `failed` 결과는 순위에서 제외되지만 전체 실행 결과에는 오류와 실행 환경 정보가 표시됩니다.
- 엔진별 상세 카드에서 시간, 추가 메모리, 피크 RSS, 마스크 compactness, 해상도, backend/provider/model, cold/warm 여부, 단계별 시간을 확인합니다.

## 8. 상태와 지표 해석

### 엔진 상태

| UI 상태 | 프로토콜 상태 | 의미 |
| --- | --- | --- |
| 성공 | `success` | 요청한 엔진이 실제 출력을 만들었으며 순위 조건을 만족할 수 있음 |
| 사용 불가 | `unavailable` | 의존성, 체크포인트 또는 요청 provider가 없어 엔진을 실행할 수 없음 |
| 실패 | `failed` | 엔진 초기화 또는 처리 중 오류 발생 |

현재 엔진 구현은 체크포인트나 라이브러리가 없을 때 다른 알고리즘으로 자동 대체하지 않습니다. 따라서 일반적인 미설치 상태는 `unavailable`로 정확히 표시됩니다.

전체 요청은 모든 엔진이 사용 가능한 결과를 내면 `측정 완료`, 일부만 사용 가능하면 `일부 엔진 측정 완료`, 하나도 사용 가능한 결과를 내지 못하면 `실행 실패`가 됩니다.

### 측정 지표

- **처리 시간**: 단조 시계로 측정한 전체 wall time입니다. 이미지 로드, 모델 준비, 전처리, 추론, 후처리, PNG 저장을 포함합니다.
- **추가 피크 메모리**: 엔진 실행 시작 시 Python 워커 RSS 대비 실행 중 관찰한 최대 RSS 증가량입니다.
- **피크 RSS**: 실행 중 관찰한 Python 워커 프로세스의 절대 최대 RSS입니다.
- **단계별 시간**: `load_image_ms`, `model_load_ms`, `preprocess_ms`, `inference_ms`, `postprocess_ms`, `save_ms` 등 엔진이 보고한 세부 구간입니다.
- **새 세션(cold)**: 해당 실행 전에 모델 세션 또는 모델 객체가 메모리에 없었습니다.
- **세션 재사용(warm)**: 상주 워커가 이전에 만든 모델 자원을 재사용했습니다.
- **마스크 compactness**: 마스크 형상의 진단값일 뿐 정확도나 시각 품질 점수가 아닙니다.

RSS는 5ms 간격 샘플링 값이므로 매우 짧은 메모리 피크를 놓칠 수 있습니다. 또한 엔진은 한 워커에서 순차 실행되므로 allocator 캐시와 이전 엔진의 상주 모델이 baseline/피크 RSS에 영향을 줄 수 있습니다. 동일 조건 비교 시 입력, provider, 스레드 수, resident model 제한을 고정하고 cold와 warm 결과를 구분하십시오.

정답(GT) 마스크가 제공되지 않으므로 IoU, 경계 정확도 또는 종합 품질 순위는 계산하지 않습니다. 결과 품질은 Compare 화면의 여러 배경과 알파 마스크를 사용해 별도로 판단해야 합니다.

## 9. Python CLI 사용

Flutter 없이 단일 프로세스에서 엔진 동작을 확인할 수 있습니다. 저장소 루트와 앱이 사용하는 같은 Python 환경에서 실행하십시오.

단일 엔진:

```bash
python backend/engine_runner.py \
  --image assets/samples/sample1_pencil_case.jpg \
  --engine watershed \
  --output_dir /tmp/comparenukki-output
```

전체 엔진:

```bash
python backend/engine_runner.py \
  --image assets/samples/sample1_pencil_case.jpg \
  --engine all \
  --output_dir /tmp/comparenukki-output
```

사용 가능한 엔진 ID:

```text
grabcut
watershed
rembg_u2net
isnet
birefnet
rmbg
inspyrenet
mobilesam
```

CLI stdout에는 `status`, 입력 SHA-256, 엔진별 `results`를 포함한 JSON이 출력됩니다. 런타임 로그는 stderr로 분리됩니다. 결과 PNG는 다음 형태로 생성됩니다.

```text
<output_dir>/<입력 파일명>/<engine_id>_result.png
<output_dir>/<입력 파일명>/<engine_id>_mask.png
```

`result.png`는 알파 채널을 포함한 BGRA PNG이고 `mask.png`는 회색조 알파 마스크입니다. 유효한 CLI 요청이면 일부 또는 모든 엔진이 `unavailable`/`failed`여도 프로세스가 종료 코드 0을 반환할 수 있으므로 종료 코드만 보지 말고 JSON의 전체 `status`와 각 결과의 `status`, `error`를 확인하십시오. 이미지가 없으면 종료 코드 1, 알 수 없는 엔진 ID이면 종료 코드 2입니다.

`engine_runner.py`는 일회성 프로세스이므로 서로 다른 CLI 호출 사이에 모델 세션을 재사용하지 않습니다. warm 세션과 스트리밍 동작은 앱이 사용하는 `engine_worker.py` 상주 워커에서 제공됩니다.

## 10. 결과 파일 수명

앱 실행 결과는 사용자 문서 폴더가 아니라 운영체제의 임시 디렉터리 아래 `comparenukki/outputs/<request-id>`에 저장됩니다.

- 최근 요청 3개의 디렉터리만 유지하며 네 번째 요청을 시작하면 가장 오래된 디렉터리를 삭제합니다.
- 앱이 정상 종료되어 BLoC/service가 dispose되면 해당 앱 세션이 만든 임시 결과를 삭제합니다.
- 다음 실행에서 7일보다 오래된 잔여 결과 디렉터리를 정리합니다.

따라서 결과를 영구 보관해야 하면 앱이 실행 중일 때 별도로 복사해야 합니다. 현재 UI에는 결과 내보내기 기능이 없습니다. CLI의 `--output_dir` 결과에는 앱의 이 자동 정리 정책이 적용되지 않습니다.

## 11. 문제 해결

### 벤치마크 실행 버튼이 비활성화됨

Web 또는 모바일 대상으로 실행 중인지 확인하십시오. 로컬 워커는 데스크톱에서만 지원됩니다. `flutter devices`로 `macos`, `windows`, `linux` 중 현재 운영체제의 대상을 선택하십시오.

### Python 워커 또는 backend를 찾을 수 없음

- 개발 실행은 저장소 루트에서 시작하십시오.
- 가상환경을 활성화하고 `python -c "import cv2, psutil; print('OK')"`를 실행하십시오.
- `COMPARENUKKI_PYTHON`과 `COMPARENUKKI_BACKEND_DIR`을 절대경로로 설정한 뒤 같은 터미널에서 `flutter run`을 실행하십시오.
- `COMPARENUKKI_BACKEND_DIR`에는 `engine_worker.py`가 직접 있어야 합니다. 저장소에서는 `<repo>/backend`입니다.

### 특정 모델 엔진이 사용 불가로 표시됨

지표 비교의 해당 엔진 오류 메시지를 먼저 확인합니다. 다음 세 조건을 모두 점검하십시오.

1. 앱이 사용하는 Python에 요구 패키지가 설치되어 있는가?
2. 체크포인트 환경변수가 실제 읽기 가능한 파일의 절대경로인가?
3. 체크포인트가 해당 엔진 구현과 호환되는가?

앱은 누락된 모델을 네트워크에서 받지 않으며 다른 엔진으로 대체하지 않습니다. 먼저 모델 없는 `watershed` CLI를 실행해 공통 Python/OpenCV 환경과 모델 문제를 분리할 수 있습니다.

### ONNX provider가 unavailable이라고 나옴

현재 Python에서 사용 가능한 provider를 확인합니다.

```bash
python -c "import onnxruntime as ort; print(ort.get_available_providers())"
```

출력 목록에 있는 값을 `NUKKI_ORT_PROVIDER`로 사용하십시오. CPU 설치에서는 보통 `CPUExecutionProvider`를 사용합니다.

### MobileSAM의 CUDA/MPS 오류

```bash
python -c "import torch; print('CUDA', torch.cuda.is_available()); print('MPS', hasattr(torch.backends, 'mps') and torch.backends.mps.is_available())"
```

사용할 수 없는 장치를 `MOBILESAM_DEVICE`에 지정하면 엔진이 `unavailable`이 됩니다. 우선 `cpu`로 검증한 뒤 장치별 PyTorch 설치를 점검하십시오.

### 메모리가 부족하거나 모델 로드가 지나치게 무거움

- `NUKKI_MAX_RESIDENT_MODELS=1`로 상주 모델 수를 줄이거나 `0`으로 재사용을 끕니다.
- `NUKKI_ORT_THREADS`를 줄여 CPU 동시 작업량을 제한합니다.
- 전체 앱 실행 전에 CLI에서 엔진을 하나씩 검증합니다.

resident 제한을 줄이면 메모리는 절약되지만 다음 실행의 모델 로드 시간이 늘어날 수 있습니다.

### 3분 후 워커가 종료됨

앱 요청 전체의 기본 timeout입니다. 현재 UI에는 timeout 변경 옵션이나 개별 엔진 선택기가 없습니다. CLI의 `--engine`으로 느린 엔진을 개별 진단하고 장치/provider 설정을 확인하십시오. 앱 timeout을 변경하려면 `NukkiService.runBenchmark` 호출 또는 기본값을 코드에서 조정해야 합니다.

### 취소 후 다음 실행이 cold로 표시됨

정상 동작입니다. 취소와 timeout은 네이티브 추론 중단을 보장하기 위해 워커 프로세스를 종료하므로 모든 상주 모델 세션이 해제됩니다.

### 앱을 닫은 뒤 결과 PNG가 사라짐

정상적인 임시 파일 정리 동작입니다. 영구 결과가 필요하면 CLI에서 보존할 `--output_dir`을 지정하거나 앱 종료 전에 파일을 복사하십시오.

## 12. 기본 검증 명령

코드를 변경한 뒤 저장소 루트에서 다음을 실행합니다.

```bash
flutter analyze
flutter test
python -m unittest discover -s backend/tests -v
python -m compileall -q backend
python backend/engine_runner.py \
  --image assets/samples/sample1_pencil_case.jpg \
  --engine watershed \
  --output_dir /tmp/comparenukki-smoke
```

배포 빌드와 패키징 절차는 [deploy.md](deploy.md)를 참고하십시오.
