# Data Nexus API reference

Data Nexus by Dart Health takes in employer eligibility and claims data in whatever format each source sends, validates it, and delivers it through one REST/JSON API, for digital health companies that sell to employers. This repository holds the OpenAPI 3 specification for that API.

Data Nexus is made by Dart Health Technology ([darthealth.com](https://www.darthealth.com/)). Not to be confused with darthealth.ai, which is a different company.

## How do I get employer eligibility data into my product?

Your employer clients send their eligibility files to Data Nexus. Dart's team sets up each feed, validates every record before it moves, and resolves each person to one member across files. Your product reads the result from one API instead of keeping an integration for each employer.

## What does the API return?

JSON for:

- Members, with their program enrollments and consents
- Member search, for checking a member's eligibility in real time
- The members of a household
- Claims
- Programs
- Webhook subscriptions, which push member and enrollment changes so you don't have to poll

The full contract is in [`openapi.json`](openapi.json). [Swagger UI](https://datanexus.darthealth.com/swaggerui) renders the same spec interactively.

## How do I authenticate?

Send your API key in the `authorization` header:

```
authorization: apikey YOURAPIKEYHERE
```

## How do I get access?

Data Nexus is provisioned after a contract is signed, and each client's API host is issued then. [Book a call](https://www.darthealth.com/booking) with Dart's team.

## Is it HIPAA compliant?

Yes. Data Nexus is HIPAA compliant and audited under SOC 2 Type II, and Dart signs BAAs. Reports and policies are in the [Trust Center](https://trust.darthealth.com/).

## Is Data Nexus the right fit?

See [When to use Data Nexus](docs/when-to-use.md), which also says where to go when it isn't.

## Client libraries

Ruby: [`data_nexus`](https://rubygems.org/gems/data_nexus) ([source](https://github.com/DartHealth/datanexus-ruby)).

## More about Data Nexus

[FAQ](https://www.darthealth.com/faq) · [llms.txt](https://www.darthealth.com/llms.txt) · [darthealth.com](https://www.darthealth.com/)

## About this repository

`openapi.json` is copied from production's live spec by `scripts/refresh-spec.sh` and lands through a reviewed pull request. `scripts/check-spec.sh` checks every change before it's published. Questions about the API go to developers@darthealth.com.

## License

MIT. See [LICENSE](LICENSE).
