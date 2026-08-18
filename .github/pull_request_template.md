## 变更概述

请简要说明本 PR 修改了什么、为什么修改。

## 关联 Issue

- Closes #ISSUE_NUMBER(如有)

## 变更类型

- [ ] 自定义规则修改(`sources/custom/`、`sources/builtin/`)
- [ ] 上游来源/处理逻辑(`config/upstreams.json`、`scripts/`)
- [ ] 文档与模板(`README.md`、`docs/`、`templates/`)
- [ ] CI / 测试(`.github/`、`scripts/tests/`)

## 影响范围

- [ ] 仅 `main` 构建源,不影响已发布产物
- [ ] 会影响发布产物内容(请说明哪些规则集受影响)
- [ ] 涉及上游来源切换(请同步更新 `THIRD_PARTY_NOTICES.md`)

## 验证

- [ ] `make lint` 通过
- [ ] `make test` 通过
- [ ] `make test-python` 通过
- [ ] 已针对真实上游数据完成端到端验证(如涉及)

## 补充说明

任何需要维护者注意的信息。
