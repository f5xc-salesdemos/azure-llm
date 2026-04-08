# GitHub Operations Quality Benchmark — Model Comparison

**Models tested:** 6

## Scores (0–100, higher is better)

| Model                           |   Code Review |   Commit Message |   Gh Cli |   Issue Triage |   Pr Description |   Overall |
|---------------------------------|---------------|------------------|----------|----------------|------------------|-----------|
| gemma-4-31b                     |          79.3 |             73.8 |     98.5 |           78.5 |             89.3 |      83.9 |
| Qwen2.5-Coder-7B-Instruct       |          74.2 |             77.6 |     91.5 |           76.3 |             88.6 |      81.6 |
| Qwen3-Coder-30B-A3B-Instruct    |          79.3 |             86.7 |     90.5 |           67.3 |             83.6 |      81.5 |
| Phi-4-mini-instruct             |          76.6 |             80.5 |     84   |           69.3 |             83.1 |      78.7 |
| DeepSeek-Coder-V2-Lite-Instruct |          69.6 |             77   |     85.5 |           74.5 |             81.7 |      77.7 |
| starcoder2-15b                  |           0   |              0   |      0   |            0   |              0   |       0   |

## Details

### deepseek-ai/DeepSeek-Coder-V2-Lite-Instruct
- Duration: 52.4s
- Test cases: 56
- Overall: **77.7**/100

### gemma-4-31b
- Duration: 67.9s
- Test cases: 56
- Overall: **83.9**/100

### microsoft/Phi-4-mini-instruct
- Duration: 10.1s
- Test cases: 56
- Overall: **78.7**/100

### Qwen/Qwen2.5-Coder-7B-Instruct
- Duration: 26.1s
- Test cases: 56
- Overall: **81.6**/100

### Qwen/Qwen3-Coder-30B-A3B-Instruct
- Duration: 33.9s
- Test cases: 56
- Overall: **81.5**/100

### bigcode/starcoder2-15b
- Duration: 0.1s
- Test cases: 56
- Overall: **0.0**/100
