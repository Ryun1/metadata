# Governance Metadata Testing

This repo contains examples of what off-chain governance metadata anchors could look like.

I have based the metadata on [CIP-0100? | Governance Metadata](https://github.com/cardano-foundation/CIPs/pull/556) at commit [68b35d7](https://github.com/cardano-foundation/CIPs/pull/556/).

I used [this Blake2b-256](https://toolkitbay.com/tkb/tool/BLAKE2b_256) hashing tool to create the hashes.

### Examples

#### Governance Action
- [ga.jsonld](./ga.jsonld)
- Hash: `1726900bdc2a06d696c3130f12c8f0d3aecc566a9d4154a2048269bb4a84b012`
- Accessible URL: https://raw.githubusercontent.com/Ryun1/metadata/main/ga.jsonld

#### New constitution Metadata
- [ga2.jsonld](./ga2.jsonld)
- Hash: `326267a12f1d8f0db5584cc332b6409d53d3c1ed44b8050718e28a36484cad32`
- Accessible URL: https://raw.githubusercontent.com/Ryun1/metadata/main/ga2.jsonld

#### New Constitution
- [c.txt](./c.txt)
- Hash: `328b76f58bb5d695dc4c2122caafd9269cb9ef8717a5c4ba86861924c3ac4a17`
- Accessible URL: https://raw.githubusercontent.com/Ryun1/metadata/main/c.txt

#### DRep
- todo

#### Vote
- todo

### Motivation
- To have a tool to visually show people what metadata anchors could look like.
- To have some mock data to use during development of tooling.