# Governance Metadata Testing

This repo contains examples of what off-chain governance metadata anchors could look like.

## Background

[CIP-1694](https://github.com/cardano-foundation/CIPs/blob/master/CIP-1694/README.md) introduces the concept of governance metadata anchors, which provide a mechanism to link off-chain metadata to on-chain governance events.

Having standards for how this off-chain metadata should look will enable rich user experiences in governance tooling.

[CIP-0100 | Governance Metadata](https://github.com/cardano-foundation/CIPs/tree/master/CIP-0100) was developed by the community to act as a base standard for all governance metadata.
This defines best practices and generic fields which can be used for anchors.

CIP-100 was designed to be expanded upon by downstream CIPs.
These CIPs will extend the property vocabulary to cater to different types ot metadata anchor.

The Governance Metadata Working Group has been running workshops to start development on these downstream CIPs.
Starting with Governance Action metadata anchors with [CIP-0108? | Governance Metadata - Governance Actions](https://github.com/cardano-foundation/CIPs/pull/632).

## Examples

I used [this Blake2b-256](https://toolkitbay.com/tkb/tool/BLAKE2b_256) hashing tool to create the hashes.

### [CIP-100 Examples](./cip100/)

Please note, due to the base nature of CIP-100, it has very few properties/fields so it between examples things don't change too much.

#### Governance Action
- [ga.jsonld](./cip100/ga.jsonld)
- Hash: `fcfa077e00ff4e2afdda9380614495be3053c046a7b2a6a691cde1ca460db03b`
- Github hosted: https://raw.githubusercontent.com/Ryun1/metadata/main/cip100/ga.jsonld
- IPFS hosted: ipfs://Qmb5K1kFgNZwRbP3VbezWitpevcnNBrF3P6JcFdCFtMSrb

#### DRep Registration
- [reg.jsonld](./cip100/reg.jsonld)
- Hash: `4e76197328bbe21586b46d23ccb15ac1da83149c6b7771448f32add84c1e645f`
- Github hosted: https://raw.githubusercontent.com/Ryun1/metadata/main/cip100/reg.jsonld
- IPFS hosted: ipfs://QmcfdhYp2itxvjF2cTbCSDqNPZ56Q8VdYPjy5FGiHaeRTe

### [CIP-108 Examples](./cip108/)

- todo