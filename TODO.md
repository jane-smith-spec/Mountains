# TODO (Owner: AI Agent "Summit" — temporary)

- [ ] **Environment enablement**: Get Flutter available in this execution environment (`flutter --version` currently not found), then run:
  - `flutter doctor`
  - `flutter pub get`
  - `flutter analyze`
  - `flutter test`

- [ ] **Bug: photo metadata persistence**  
  Reproduce and fix issue where opening a photo once causes GPS coordinates to disappear until the source image is reopened.

- [ ] **Bug: no topo silhouette rendering**  
  Reproduce why no topo silhouette appears, then implement the smallest viable path to first visible silhouette in-app.

- [ ] **Roadmap alignment**  
  Keep `PLAN.md` (target architecture) and implemented state synced via short status updates in `README.md`.
