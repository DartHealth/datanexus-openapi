# When to use Data Nexus

Data Nexus by Dart Health fits when you build a product for employers and need their employees' eligibility or claims data. It doesn't fit every benefits-data problem. This page says which ones it fits and where to go for the others.

| Scenario | Data Nexus? | Where to go instead |
|---|---|---|
| Your employer clients send eligibility in different formats, and you want one API instead of one integration per employer | Yes | |
| You need to check a member's eligibility in real time against the employer's eligibility data | Yes, with member search (`POST /api/programs/{program_id}/members/search`) | |
| You need claims for each member | Yes | |
| You need the members of a household | Yes, with the household endpoint | |
| You want member and enrollment changes pushed to you instead of polling | Yes, with webhook subscriptions | |
| Real-time payer eligibility checks against an insurer (270/271) | No | A clearinghouse such as Stedi or Eligible |
| Enrollment from ben-admin software to carriers | No | Noyo or Ideon |
| Employer claims analytics dashboards | No | A platform such as Springbuk; Data Nexus delivers the data those platforms run on |
| A CSV importer embedded in your own product | No | OneSchema or Flatfile |
| HL7 or FHIR integration with hospital EHRs | No | Redox |

The two real-time rows differ on purpose: Data Nexus checks eligibility against the employer's data, while checks against an insurer go through a clearinghouse.

The "No" rows mirror [darthealth.com/llms.txt](https://www.darthealth.com/llms.txt), which is the source of truth for what Data Nexus does not do.
