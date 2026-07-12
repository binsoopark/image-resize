# Image Resize

여러 이미지를 한 번에 **중심 기준으로 크롭**하거나 **비율과 관계없이 목표 크기로 리사이즈**하는 도구입니다.

웹 버전과 macOS 네이티브 앱을 함께 제공합니다. 크롭 시 입력 이미지가 목표 크기보다 작으면 **cover 방식으로 확대한 뒤 중심을 기준으로 크롭**합니다.

## 주요 기능

- 여러 이미지 일괄 처리
- 드래그 앤 드롭으로 파일 추가
- 목표 너비·높이(px) 지정
- **크롭 실행** — 중심 기준 크롭 (작은 이미지 자동 확대 후 크롭)
- **리사이즈 실행** — 비율 무시 stretch 리사이즈
- **투명도 제거** — 알파 채널 제거 (아이폰 앱 등록용)
- PNG / JPEG 출력 형식 지원
- 처리 결과 미리보기 및 일괄 저장

## 프로젝트 구조

```
image-resize/
├── web/                 # 브라우저용 웹 앱
│   ├── index.html
│   ├── style.css
│   └── app.js
└── macos/               # macOS 네이티브 앱 (SwiftUI)
    ├── project.yml      # XcodeGen 설정
    ├── ImageResize.xcodeproj
    └── ImageResize/     # Swift 소스
```

## 처리 방식

### 크롭 실행

1. 목표 크기(너비 × 높이)를 입력합니다.
2. 각 이미지에 대해 다음을 수행합니다.
   - 가로 또는 세로가 목표보다 작으면, 목표 영역을 채울 때까지 **비율을 유지하며 확대**합니다.
   - 확대(또는 원본) 이미지의 **중심**을 기준으로 목표 크기만큼 잘라냅니다.
3. 결과 파일명은 `원본이름_cropped_800x600.확장자` 형식입니다.

### 리사이즈 실행

1. 목표 크기(너비 × 높이)를 입력합니다.
2. 각 이미지를 **비율을 유지하지 않고** 목표 너비·높이에 맞춰 늘리거나 줄입니다.
3. 결과 파일명은 `원본이름_resized_800x600.확장자` 형식입니다.

### 투명도 제거

- 체크 시 투명 영역을 **흰색 배경**으로 채운 뒤 알파 채널을 제거합니다.
- 아이폰 앱 등록 시 "알파 채널 또는 투명도를 포함할 수 없다" 오류 방지에 사용합니다.
- macOS: 선택한 형식(PNG/JPEG) 그대로 알파 없는 RGB로 저장
- Web: PNG/WebP 선택 시 알파 없는 JPEG로 저장

## Web 사용법

별도 빌드 없이 정적 파일만으로 동작합니다.

### 로컬 실행

```bash
cd web
python3 -m http.server 8765
```

브라우저에서 [http://localhost:8765](http://localhost:8765) 를 엽니다.

### 사용 순서

1. 드롭 영역에 이미지를 드래그하거나 클릭해서 여러 파일을 선택합니다.
2. 너비·높이·출력 형식을 설정합니다.
3. **크롭 실행** 또는 **리사이즈 실행** 버튼을 누릅니다.
4. **전체 다운로드** 또는 각 카드의 **다운로드**로 저장합니다.

### 다운로드 방식

- **Chrome / Edge**: 폴더 선택 API로 한 번에 여러 파일 저장
- **그 외 브라우저 / 폴더 선택 취소 시**: ZIP 파일로 일괄 다운로드

> ZIP 다운로드는 CDN의 JSZip을 사용하므로 인터넷 연결이 필요합니다.

## macOS 앱 사용법

macOS 13 이상, Xcode 15 이상을 권장합니다.

### Xcode에서 실행

```bash
open macos/ImageResize.xcodeproj
```

Xcode에서 **Run (⌘R)** 으로 앱을 실행합니다.

### 터미널에서 빌드

```bash
cd macos
xcodebuild -project ImageResize.xcodeproj -scheme ImageResize -configuration Debug build
```

빌드된 앱은 DerivedData 아래 `Image Resize.app` 으로 생성됩니다.

### 앱 사용 순서

1. 드롭 영역에 이미지를 드래그하거나 **이미지 추가** / **⌘O** 로 파일을 선택합니다.
2. 너비·높이·출력 형식을 설정합니다.
3. **크롭 실행** 또는 **리사이즈 실행** 을 누릅니다.
4. **전체 저장** 으로 폴더를 선택해 일괄 저장하거나, 각 항목에서 개별 저장 / Finder에서 보기를 사용합니다.

macOS 앱은 `NSOpenPanel` / `NSSavePanel` 을 사용하므로 폴더 선택과 다중 저장이 웹보다 자연스럽게 동작합니다.

### XcodeGen으로 프로젝트 재생성

`project.yml` 을 수정한 경우:

```bash
cd macos
xcodegen generate
```

## 지원 형식

### 입력

PNG, JPEG, WebP, GIF, HEIC, TIFF, BMP 등 일반적인 이미지 형식

### 출력

- Web: PNG, JPEG, WebP
- macOS: PNG, JPEG

## 개발 환경

| 모듈 | 기술 |
|------|------|
| Web | HTML, CSS, Vanilla JavaScript, Canvas API |
| macOS | SwiftUI, AppKit, Core Graphics |

## 라이선스

MIT License
