# 🚗 TAS (Traffic/Tracking App for Simulator) Flutter

> **Ttubu** 팀의 TAS Flutter 애플리케이션 레포지토리입니다.
> CARLA 시뮬레이터 및 Ubuntu 서버와의 실시간 데이터 연동 및 모니터링을 지원하는 클라이언트 앱입니다.

## 💡 프로젝트 개요

이 프로젝트는 Ubuntu 서버 환경에서 구동되는 **CARLA 자율주행 시뮬레이터**의 데이터를 실시간으로 수신하고 제어하기 위해 제작된 Flutter 애플리케이션입니다. 위치 기반 데이터(Latitude/Longitude) 처리 및 **FastAPI(Flask) 기반 백엔드**와의 통신을 통해 시뮬레이터 환경과 매끄럽게 동기화됩니다.

## ✨ 주요 기능 (Features)

*   **🔄 Ubuntu Server & CARLA Sync:** CARLA 시뮬레이터와의 실시간 상태 동기화
*   **📍 Location Data Processing:** 로컬 위도/경도(Latitude/Longitude) 데이터 수집 및 처리
*   **📡 FastAPI Integration:** FastAPI/Flask 기반 서버와의 빠르고 안정적인 API 통신
*   **🌐 Multi-Platform Support:** Android, Web, Windows 등 다양한 플랫폼 지원 (Flutter 기반)
*   **🇰🇷 Korean Localization:** 한국어 인터페이스 지원

## 🛠 기술 스택 (Tech Stack)

*   **Frontend:** Flutter (Dart)
*   **Backend:** FastAPI, Flask, Python, Ubuntu Server
*   **Simulator:** CARLA Simulator

## 📁 디렉토리 구조 (Directory Structure)

```text
tas_flutter/
├── android/          # Android 네이티브 설정 파일
├── assets/           # 이미지, 폰트 등 정적 리소스 파일
├── lib/              # ⭐ 핵심 Flutter 코드 (UI, 비즈니스 로직, API 연동 등)
├── test/             # 유닛 및 위젯 테스트 코드
├── web/              # Web 빌드 설정 파일
├── windows/          # Windows 데스크톱 빌드 설정 파일
├── .gitignore        # Git 버전 관리 제외 파일 목록
├── pubspec.yaml      # ⭐ Flutter 패키지 의존성 및 프로젝트 설정 파일
└── README.md         # 프로젝트 설명서 (현재 파일)
```

## 🚀 시작하기 (Getting Started)

### 1. 사전 요구 사항 (Prerequisites)
이 프로젝트를 실행하기 위해서는 다음 환경이 필요합니다.
*   [Flutter SDK](https://docs.flutter.dev/get-started/install) (버전 확인 필요)
*   Dart SDK
*   Android Studio 또는 VS Code

### 2. 설치 및 실행 (Installation)
1. 레포지토리를 클론합니다.
   ```bash
   git clone https://github.com/Ttubu/tas_flutter.git
   cd tas_flutter
   ```
2. 필요한 패키지를 설치합니다.
   ```bash
   flutter pub get
   ```
3. 앱을 실행합니다. (연결된 디바이스나 에뮬레이터 필요)
   ```bash
   flutter run
   ```
