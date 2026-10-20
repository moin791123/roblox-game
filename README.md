# 귀여운 펫 모으기

Rojo로 관리하는 로블록스 게임 프로젝트입니다.

## 실행 방법
1. Roblox Studio에 Rojo 플러그인을 설치합니다.
2. 이 폴더에서 `rojo serve`를 실행합니다.
3. Studio의 Rojo 플러그인에서 Connect를 누르면 코드가 실시간으로 동기화됩니다.

## 폴더 구조
- `src/server` : 서버 스크립트 (ServerScriptService)
- `src/client` : 클라이언트 스크립트 (StarterPlayerScripts)
- `src/shared` : 공용 모듈 (ReplicatedStorage)

## 지금 들어 있는 기능
- 맵 곳곳의 코인을 밟으면 코인이 올라가요.
- 알 앞에서 E 키를 꾹 누르면 코인을 내고 펫이 나와요.
- 나온 펫은 최대 3마리까지 졸졸 따라다녀요.
- 펫 종류, 확률, 알 가격은 `src/shared/Config.luau`에서 바꿀 수 있어요.
