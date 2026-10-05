# Steward-GRC 🧭

> 📜 Open-source policy, procedure and compliance management, built as a set of small services.

Steward-GRC is an open-source, Apache-2.0 licensed policy and compliance management
system. It keeps an organisation's policies and procedures in one place, takes them
through multi-stage approval workflows, tracks who has read and acknowledged them, and
backs every change with a hash-chained, independently verifiable audit trail. It's
built as a set of small services rather than one monolith, with per-category access
rules, single sign-on and second factors, and runs on any Kubernetes cluster.

🏠 **Home:** [steward-grc.com](https://steward-grc.com)

## 🧩 Services

- [steward-core](https://github.com/Steward-GRC/steward-core): categories, templates, policies, versions and sensitivity.
- [steward-workflow](https://github.com/Steward-GRC/steward-workflow): approval stages, quorum, group approvals, reassignment, bulk decisions and due dates.
- [steward-obligations](https://github.com/Steward-GRC/steward-obligations): obligations, acknowledgements, completion reports and notifications.
- [steward-delivery](https://github.com/Steward-GRC/steward-delivery): server-side rendering, version diffs, shared read-only links and PDF export requests.
- [steward-pdf-renderer](https://github.com/Steward-GRC/steward-pdf-renderer): the PDF render operator, with a PdfRender resource and a headless Chromium job per render.
- [steward-collab](https://github.com/Steward-GRC/steward-collab): live co-editing of drafts, co-editing tokens and snapshot flush.
- [steward-reporting](https://github.com/Steward-GRC/steward-reporting): anonymous and named compliance reports, officer case work, breach assessment and notification deadlines.
- [steward-ai](https://github.com/Steward-GRC/steward-ai): cited answers, drafting, review and summaries behind one provider interface.
- [steward-gateway](https://github.com/Steward-GRC/steward-gateway): the GraphQL edge for the browser, with sessions, sign-in, first-run setup, the co-editing proxy and document extract.
- [steward-web](https://github.com/Steward-GRC/steward-web): the staff and admin web apps, the docs guide and the UI kit.

## 🔐 Identity, access and audit

- [steward-identity](https://github.com/Steward-GRC/steward-identity): users, groups, roles, sign-in factors and SSO connections.
- [steward-authz](https://github.com/Steward-GRC/steward-authz): the access-rule engine and permission catalog shared by the Steward services.
- [steward-audit](https://github.com/Steward-GRC/steward-audit): the tamper-evident, hash-chained audit service.

## 🤝 Contributing

- [Contributing guide](https://github.com/Steward-GRC/.github/blob/main/.github/CONTRIBUTING.md), with the DCO sign-off
- [Code of Conduct](https://github.com/Steward-GRC/.github/blob/main/.github/CODE_OF_CONDUCT.md)
- [Security policy](https://github.com/Steward-GRC/.github/blob/main/.github/SECURITY.md)
- [Support](https://github.com/Steward-GRC/.github/blob/main/.github/SUPPORT.md)
- [Governance](https://github.com/Steward-GRC/.github/blob/main/GOVERNANCE.md) and [maintainers](https://github.com/Steward-GRC/.github/blob/main/MAINTAINERS.md)

## 📄 Licence

[Apache-2.0](https://github.com/Steward-GRC/.github/blob/main/LICENSE).
