### Retained memory, Ruby 4.0.5, YJIT on (median of 5 processes; baseline recorded 2026-10-20T17:34:10Z)

| phase (growth since the previous phase) | baseline KB | current KB | baseline live slots | current live slots |
|---|---:|---:|---:|---:|
| require | 34.0 | 33.7 | 877 | 835 |
| 200 classes x 50 annotated methods | 3116.2 | 3116.3 | 72226 | 72235 |
| annotations_for on every method | 0.4 | 0.4 | 805 | 807 |
| annotated_with on every class | 1.9 | 1.9 | 1006 | 1008 |
| global Adornment.annotated_with | 362.2 | 362.2 | 409 | 410 |
