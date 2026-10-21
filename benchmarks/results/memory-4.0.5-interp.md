### Retained memory, Ruby 4.0.5, YJIT off (median of 5 processes; baseline recorded 2026-10-20T17:34:10Z)

| phase (growth since the previous phase) | baseline KB | current KB | baseline live slots | current live slots |
|---|---:|---:|---:|---:|
| require | 34.0 | 33.7 | 877 | 835 |
| 200 classes x 50 annotated methods | 3116.2 | 3116.3 | 72295 | 72304 |
| annotations_for on every method | 0.4 | 0.4 | 813 | 815 |
| annotated_with on every class | 0.2 | 0.2 | 1018 | 1021 |
| global Adornment.annotated_with | 2.8 | 2.9 | 214 | 215 |
