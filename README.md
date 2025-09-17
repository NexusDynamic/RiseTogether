# RiseTogether

Video of recent update in action (12 September 2025): https://www.youtube.com/watch?v=odbIwJH6IcY


# headless mode

```bash
set RISETOGETHER_CONFIG (cat ./risetogether_config.json) && RISETOGETHER_CONFIG=$RISETOGETHER_CONFIG flutter -dmacos run --dart-define=APP_MODE=headless_server  --release --no-pub
```
