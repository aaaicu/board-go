---
description: GitHub and Gitflow Workflow 
---

# GitHub 및 Gitflow 작업 방법

이 워크플로우를 통해 GitHub 저장소를 가져오고(fork/clone) Gitflow 기반 환경을 설정하는 방법을 정의합니다.

1. **저장소 클론(Clone)**
   - 전달받은 GitHub 저장소 URL을 통해 클론을 진행합니다.
   ```bash
   git clone <REPOSITORY_URL> .
   ```

2. **Gitflow 초기화**
   - 저장소 클론 후 Gitflow를 초기화하여 `master`(main)와 `develop` 브랜치를 생성하고 관리할 수 있도록 구성합니다.
   // turbo
   ```bash
   git checkout -b develop || true
   # 필요한 경우 기본 git flow init 명령 수행
   ```

3. **기본 설정 확인**
   - 현재 브랜치 상태와 원격 저장소 설정을 체크합니다.
   ```bash
   git status
   git remote -v
   ```
