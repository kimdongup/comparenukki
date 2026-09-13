# CompareNukki 배포 가이드

이 문서는 현재 저장소를 기준으로 배포 산출물을 만드는 방법과, 실제 벤치마크 실행에 필요한 외부 런타임을 설명합니다. CompareNukki 데스크톱 앱은 Flutter UI와 Python 워커로 구성됩니다. **Flutter 앱만 복사해서는 모든 엔진이 실행되지 않습니다.**

개발 환경 준비와 앱·CLI 사용법은 [usage.md](usage.md)를 참고하십시오.

## 1. 현재 배포 상태

| 대상 | 프로젝트 상태 | 벤치마크 실행 | 비고 |
| --- | --- | --- | --- |
| macOS | 러너 있음 | 지원 | 현재 빌드에서 `backend` Flutter asset 포함을 확인함 |
| Windows | 러너 없음 | 코드상 지원 | Windows 호스트에서 러너 생성과 실기기 검증 필요 |
| Linux | 러너 없음 | 코드상 지원 | Linux 호스트에서 러너 생성과 실기기 검증 필요 |
| Web | 러너 있음 | 미지원 | 정적 UI만 배포 가능하며 로컬 Python 실행 버튼은 비활성화됨 |
| Android/iOS | 러너 있음 | 미지원 | 로컬 Python 워커를 실행하지 않음 |

데스크톱 지원 판정은 `macOS`, `Windows`, `Linux`로 제한되어 있습니다. 현재 저장소에서 직접 빌드·확인된 데스크톱 대상은 macOS이며, Windows/Linux용 `windows/`, `linux/` 디렉터리는 아직 없습니다.

## 2. 배포물에 포함되는 것과 포함되지 않는 것

`pubspec.yaml`은 다음 Python 소스를 Flutter asset으로 등록합니다.

- `backend/engine_worker.py`
- `backend/engine_registry.py`
- `backend/engines/` 아래 엔진 소스

macOS 앱에서는 다음과 같은 번들 경로에 이 파일들이 포함됩니다.

```text
comparenukki.app/Contents/Frameworks/App.framework/Resources/
  flutter_assets/backend/engine_worker.py
```

Windows/Linux 표준 Flutter 번들에서는 앱 실행 파일 옆 `data/flutter_assets/backend`를 찾도록 구현되어 있습니다. 이 경로는 해당 플랫폼 러너를 만든 후 실제 release 산출물에서 반드시 확인해야 합니다.

다음 항목은 현재 앱에 포함되거나 자동 설치되지 않습니다.

- Python 실행 파일
- `backend/requirements.txt`의 Python 패키지
- ONNX, PyTorch 모델 체크포인트
- InSPyReNet 및 MobileSAM의 선택 패키지
- Windows/Linux 설치 프로그램
- macOS 배포 인증서, Hardened Runtime 설정, 공증 구성
- 원격 추론 서버나 Web용 API

또한 `backend/requirements.txt`와 `backend/engine_runner.py` 자체는 현재 Flutter asset 목록에 없습니다. 운영 환경에는 저장소 또는 별도 배포 패키지에서 requirements를 제공해야 합니다.

## 3. 권장 배포 구성

현재 구현에는 내장 Python 배포 기능이 없으므로, 관리되는 데스크톱 환경에서는 다음 구성을 권장합니다.

```text
Flutter release 앱
  └─ 번들 안의 backend Python 소스

운영체제에 별도 설치
  ├─ 고정된 Python 가상환경
  ├─ 검증한 Python 패키지
  └─ 검증한 모델 파일
```

앱 프로세스에 최소한 `COMPARENUKKI_PYTHON`과 모델 경로 환경 변수를 전달합니다. 사용자가 Python을 별도로 설치하지 않아도 되는 단일 설치 프로그램을 원한다면, Python 런타임·native wheel·모델을 플랫폼별로 묶는 별도 패키징 작업이 필요합니다. 현재 저장소는 이를 구현하지 않습니다.

## 4. 공통 릴리스 준비

### Flutter 및 Python 검사

```bash
flutter doctor -v
flutter pub get
flutter analyze
flutter test

python3 -m venv .venv
source .venv/bin/activate
python -m pip install --upgrade pip
python -m pip install -r backend/requirements.txt
python -m pip check
python -m compileall -q backend
```

Windows PowerShell에서는 가상환경을 다음과 같이 활성화합니다.

```powershell
py -3.11 -m venv .venv
.\.venv\Scripts\Activate.ps1
python -m pip install --upgrade pip
python -m pip install -r backend\requirements.txt
python -m pip check
```

현재 requirements는 호환 버전 범위를 사용하며 완전히 고정된 lock 파일은 아닙니다. 재현 가능한 운영 배포가 필요하면 OS와 CPU 아키텍처별로 검증한 wheelhouse 또는 해시가 포함된 lock 파일을 별도로 만들고, 그 조합으로 회귀 테스트해야 합니다.

### Python 기본 의존성

`backend/requirements.txt`는 다음 core runtime을 설치합니다.

- NumPy
- OpenCV headless
- psutil
- ONNX Runtime
- Pillow

이 구성으로 OpenCV 엔진과 ONNX 기반 엔진 코드를 실행할 수 있습니다. ONNX 엔진은 각각의 체크포인트가 추가로 필요합니다.

InSPyReNet과 MobileSAM은 PyTorch 및 장치별 설치 조건이 달라 core requirements에서 제외되어 있습니다.

- InSPyReNet: `transparent-background`, 호환 PyTorch, `ckpt_base.pth`
- MobileSAM: 호환 PyTorch, MobileSAM 패키지, `mobile_sam.pt`

선택 패키지는 대상 OS·CPU/GPU와 각 프로젝트의 설치 지침에 맞춰 별도로 설치하십시오. 배포 전에 패키지와 모델의 라이선스 및 재배포 허용 조건도 확인해야 합니다.

### 모델 배치

기본 ONNX/MobileSAM 모델 디렉터리는 `~/.u2net`입니다. 운영 배포에서는 사용자 홈에 암묵적으로 의존하기보다 절대 경로를 지정하는 편이 안전합니다.

```bash
export NUKKI_MODEL_DIR=/opt/comparenukki/models
export U2NET_MODEL_PATH=/opt/comparenukki/models/u2net.onnx
export ISNET_MODEL_PATH=/opt/comparenukki/models/isnet-general-use.onnx
export BIREFNET_MODEL_PATH=/opt/comparenukki/models/birefnet-general.onnx
export RMBG_MODEL_PATH=/opt/comparenukki/models/bria_rmbg14.onnx
export INSPYRENET_CHECKPOINT=/opt/comparenukki/models/ckpt_base.pth
export MOBILESAM_CHECKPOINT=/opt/comparenukki/models/mobile_sam.pt
```

Windows에서는 `C:\ProgramData\CompareNukki\models`처럼 서비스 계정과 사용자가 읽을 수 있는 경로를 사용할 수 있습니다. 모델 파일을 앱 번들에 추가하려면 용량, 업데이트 방법, 서명 무결성, 모델 라이선스를 검토한 뒤 별도 구현해야 합니다.

### 런타임 환경 변수

```bash
export COMPARENUKKI_PYTHON=/absolute/path/to/venv/bin/python3
export COMPARENUKKI_BACKEND_DIR=/absolute/path/to/backend  # 선택 사항
export NUKKI_ORT_PROVIDER=CPUExecutionProvider
export NUKKI_ORT_THREADS=4
export NUKKI_MAX_RESIDENT_MODELS=2
export NUKKI_LOG_LEVEL=WARNING
export INSPYRENET_DEVICE=cpu
export MOBILESAM_DEVICE=cpu
```

- `COMPARENUKKI_PYTHON`: 워커를 실행할 Python입니다. 운영 배포에서는 PATH의 `python3`보다 가상환경 실행 파일의 절대 경로를 권장합니다.
- `COMPARENUKKI_BACKEND_DIR`: `engine_worker.py`가 있는 디렉터리를 번들 밖에서 강제로 지정합니다. 정상적인 release bundle에서는 보통 필요하지 않습니다.
- `NUKKI_ORT_PROVIDER`: 설치된 ONNX Runtime이 실제 제공하는 provider여야 합니다.
- `NUKKI_ORT_THREADS`: ONNX Runtime intra-op thread 수입니다.
- `NUKKI_MAX_RESIDENT_MODELS`: 워커가 동시에 유지하는 무거운 모델 세션 수이며 기본값은 2입니다.
- `INSPYRENET_DEVICE`, `MOBILESAM_DEVICE`: `cpu`, `cuda`, `mps` 등 실제 PyTorch가 지원하는 값을 사용합니다.

GUI 앱은 셸 설정 파일의 환경 변수를 항상 상속하지 않습니다. 특히 Finder에서 실행한 macOS 앱은 터미널의 `.zshrc` 설정을 그대로 받는다고 가정하면 안 됩니다. 조직 배포 도구, 실행 wrapper 또는 운영체제의 프로세스 환경 구성으로 위 값을 앱 프로세스에 전달하고, 깨끗한 사용자 계정에서 확인하십시오. 현재 앱에는 이 경로를 저장하는 설정 화면이 없습니다.

## 5. macOS 배포

### 빌드

macOS 호스트에서 실행합니다.

```bash
flutter clean
flutter pub get
flutter build macos --release
```

기본 산출물은 다음 위치입니다.

```text
build/macos/Build/Products/Release/comparenukki.app
```

앱만 옮기기 전에 backend asset을 확인합니다.

```bash
test -f build/macos/Build/Products/Release/comparenukki.app/Contents/Frameworks/App.framework/Resources/flutter_assets/backend/engine_worker.py
```

현재 macOS 설정은 다음과 같습니다.

- bundle identifier: `com.comparenukki.comparenukki`
- minimum deployment target: macOS 10.15
- release entitlement의 App Sandbox: 비활성화
- network client 및 사용자 선택 파일 read/write entitlement: 선언됨
- 배포용 Developer ID와 Hardened Runtime: 저장소에서 명시적으로 구성되지 않음

공개 배포 전에는 고유 bundle identifier와 앱 메타데이터를 확정하고, Xcode의 Runner target에서 Developer ID 서명 및 Hardened Runtime을 구성한 다음 archive, 공증(notarization), staple 과정을 수행하십시오. 현재 App Sandbox가 꺼져 있으므로 Mac App Store 제출 준비가 된 구성으로 간주하면 안 됩니다. 외부 Python 실행 및 모델 접근 방식까지 포함해 App Store sandbox 정책에 맞춘 별도 설계가 필요합니다.

서명 뒤 앱 번들 내부의 Python 파일을 교체하면 코드 서명이 깨질 수 있습니다. backend를 수정했다면 Flutter 앱을 다시 빌드하고 다시 서명·공증해야 합니다. 배포 후보에서 다음을 확인합니다.

```bash
codesign --verify --deep --strict --verbose=2 \
  build/macos/Build/Products/Release/comparenukki.app
spctl --assess --type execute --verbose=4 \
  build/macos/Build/Products/Release/comparenukki.app
```

DMG/PKG 생성과 자동 업데이트는 현재 저장소에 구성되어 있지 않습니다. 선택한 배포 도구에서 앱의 서명과 공증 결과가 유지되는지 별도로 확인해야 합니다.

## 6. Windows 배포

현재 `windows/` 러너가 없으므로 Windows 호스트에서 먼저 생성합니다. 이 작업은 플랫폼 파일을 추가하므로 변경 내용을 검토하고 버전 관리에 포함하십시오.

```powershell
flutter config --enable-windows-desktop
flutter create --platforms=windows .
flutter pub get
flutter analyze
flutter test
flutter build windows --release
```

산출물은 Flutter/아키텍처 버전에 따라 `build\windows\...\runner\Release` 아래에 생성됩니다. `.exe` 하나만 배포하지 말고 해당 Release 디렉터리의 DLL과 `data`를 함께 배포해야 합니다.

backend asset 예상 경로를 실제 산출물에서 확인합니다.

```powershell
Get-ChildItem build\windows -Recurse -Filter engine_worker.py
# 예상: ...\runner\Release\data\flutter_assets\backend\engine_worker.py
```

Python 환경은 앱과 같은 CPU 아키텍처의 패키지를 사용하고, 앱을 실행하는 프로세스에 경로를 전달합니다.

```powershell
$env:COMPARENUKKI_PYTHON = 'C:\ProgramData\CompareNukki\venv\Scripts\python.exe'
$env:NUKKI_MODEL_DIR = 'C:\ProgramData\CompareNukki\models'
.\build\windows\x64\runner\Release\comparenukki.exe
```

마지막 실행 경로의 `x64` 부분은 실제 산출물에 맞게 조정합니다. MSI/MSIX 구성과 Authenticode 서명은 현재 저장소에 없습니다. 외부 배포 전에는 설치 프로그램을 별도로 만들고 실행 파일 및 필요한 DLL에 조직의 코드 서명 정책을 적용하십시오.

## 7. Linux 배포

현재 `linux/` 러너가 없으므로 대상 배포판과 같은 계열의 Linux 호스트에서 먼저 생성·빌드합니다.

```bash
flutter config --enable-linux-desktop
flutter create --platforms=linux .
flutter pub get
flutter analyze
flutter test
flutter build linux --release
```

산출물은 보통 다음 구조이며 CPU 아키텍처에 따라 중간 경로가 달라질 수 있습니다.

```text
build/linux/<architecture>/release/bundle/
```

실행 파일 하나가 아니라 `bundle` 전체를 배포합니다. 다음처럼 backend asset을 확인합니다.

```bash
find build/linux -path '*/release/bundle/data/flutter_assets/backend/engine_worker.py' -print
```

앱 실행 프로세스에 Python과 모델 경로를 전달합니다.

```bash
COMPARENUKKI_PYTHON=/opt/comparenukki/venv/bin/python3 \
NUKKI_MODEL_DIR=/opt/comparenukki/models \
./build/linux/x64/release/bundle/comparenukki
```

배포판별 native library와 Python wheel 호환성을 검사하십시오. AppImage, deb/rpm, Snap, Flatpak 패키징은 현재 구성되어 있지 않습니다. 특히 sandbox형 패키지는 호스트 Python 실행과 홈/모델 파일 접근이 차단될 수 있으므로, 권한과 런타임을 명시적으로 설계하지 않은 상태에서 현재 앱을 그대로 넣으면 안 됩니다.

## 8. Web 배포

```bash
flutter clean
flutter pub get
flutter build web --release
```

`build/web` 전체를 정적 호스팅에 올리고 HTTP(S)로 서비스합니다. `index.html`을 로컬 `file://`로 여는 방식은 배포 방법으로 사용하지 않습니다. 하위 경로에 배포한다면 Flutter의 base href 설정과 호스팅 rewrite 규칙을 함께 조정해야 합니다.

Web 빌드에서는 `dart:io` Python worker를 실행하지 않으며 벤치마크 버튼이 비활성화됩니다. 현재 원격 backend API도 없으므로 Web 배포판은 로컬 배경 제거 성능을 측정할 수 없습니다. Web에서 실제 벤치마크를 제공하려면 인증, 업로드 제한, 작업 큐, 격리, 시간 제한을 갖춘 서버 API와 Web용 service 구현이 별도로 필요합니다.

주의할 점은 Python이 실행되지 않더라도 `pubspec.yaml`의 asset 설정 때문에 `build/web/assets/backend`에 Python 소스가 포함된다는 것입니다. 현재 build에서도 이 포함을 확인했습니다. 공개 Web 배포에서 소스 노출이나 불필요한 전송 파일이 문제가 된다면, backend asset을 데스크톱 전용 패키지/빌드 단계로 분리한 뒤 배포해야 합니다. 단순히 파일을 수동 삭제하면 Flutter asset manifest와 불일치할 수 있으므로 릴리스 파이프라인에서 구조적으로 처리하십시오.

## 9. 모바일 제한

Android와 iOS 러너는 존재하지만 `NukkiService.supportsLocalWorker`가 두 플랫폼을 지원하지 않습니다. 따라서 앱은 빌드할 수 있어도 로컬 Python 벤치마크 버튼이 비활성화됩니다. 현재 상태의 모바일 산출물을 완전한 벤치마크 앱으로 배포해서는 안 됩니다. 모바일 지원에는 네이티브 추론 이식 또는 원격 backend API가 필요합니다.

Android release 설정은 현재 debug key를 사용하도록 되어 있어 공개 배포용 서명이 아닙니다. iOS에도 팀 설정이 들어 있지만, Python 워커 기능과 App Store 배포 가능성을 의미하지는 않습니다.

## 10. 보안 및 운영 주의점

- `COMPARENUKKI_PYTHON`은 앱이 실행할 프로그램을 바꾸며, `COMPARENUKKI_BACKEND_DIR`은 실행할 Python 소스를 바꿉니다. 관리자가 소유하고 일반 사용자가 수정할 수 없는 절대 경로만 지정하십시오.
- 모델 파일도 추론 프로세스가 역직렬화하거나 해석하는 입력입니다. 신뢰한 출처에서 받고 배포 시 해시를 검증하십시오.
- Python 가상환경, backend 소스, 모델 디렉터리에 최소 권한을 적용하십시오.
- 사용자 입력 이미지는 임시 디렉터리에서 처리됩니다. 앱은 자신이 만든 최근 요청 디렉터리를 정리하지만, 비정상 종료나 OS 백업까지 포함한 데이터 보존 정책을 대신하지는 않습니다.
- Web에 올린 asset은 누구나 다운로드할 수 있다고 가정하십시오. 비밀 값, 비공개 모델 또는 자격 증명을 Flutter asset에 넣지 마십시오.
- Python 워커는 로컬 프로세스이므로 악성 이미지, 취약한 native library, 과도한 메모리 사용에 대한 위험을 릴리스 패키지의 패치 정책에 포함하십시오.
- GPU provider를 배포할 때 드라이버/CUDA/ONNX Runtime/PyTorch 조합을 대상 장비별로 고정하고 검증하십시오.

## 11. 릴리스 전 체크리스트

- [ ] `pubspec.yaml`의 버전과 플랫폼별 bundle/application identifier를 확정했다.
- [ ] `flutter analyze`와 `flutter test`가 통과한다.
- [ ] Python `pip check`, `python -m unittest discover -s backend/tests -v`, backend 구문 검사가 통과한다.
- [ ] release 산출물 안에 `flutter_assets/backend/engine_worker.py`와 모든 엔진 소스가 있다.
- [ ] 깨끗한 사용자 계정에서 `COMPARENUKKI_PYTHON`과 모델 경로가 앱에 전달된다.
- [ ] 배포 대상과 같은 OS·CPU·GPU에서 8개 엔진의 성공/사용 불가 상태가 의도와 일치한다.
- [ ] Python, native wheel, 모델 파일의 버전과 해시를 릴리스 기록에 남겼다.
- [ ] 모델 및 선택 라이브러리의 사용·재배포 라이선스를 검토했다.
- [ ] macOS 서명·공증 또는 Windows 코드 서명을 실제 설치본에서 검증했다.
- [ ] Windows/Linux는 생성한 러너와 전체 bundle을 실기기에서 검증했다.
- [ ] Web 산출물에서 Python source asset 노출을 허용할지 결정했다.
- [ ] 앱 번들만 설치했을 때 Python과 모델이 자동 설치된다는 잘못된 안내가 없다.

플랫폼별 설치 프로그램, CI/CD, 자동 업데이트, 내장 Python 및 원격 Web 추론은 현재 범위 밖입니다. 이를 추가하기 전까지는 각 배포 환경에 Python 가상환경과 모델을 별도로 프로비저닝해야 합니다.

## 12. 공식 참고 자료

- [Flutter: Build and release a macOS app](https://docs.flutter.dev/deployment/macos)
- [Flutter: Build and release a Windows desktop app](https://docs.flutter.dev/deployment/windows)
- [Flutter: Build and release a Linux app](https://docs.flutter.dev/deployment/linux)
- [Flutter: Build and release a Web app](https://docs.flutter.dev/deployment/web)
- [Apple: Notarizing macOS software before distribution](https://developer.apple.com/documentation/security/notarizing-macos-software-before-distribution)
- [Apple: Preparing your app for distribution](https://developer.apple.com/documentation/xcode/preparing-your-app-for-distribution)
