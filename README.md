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

I used [this JSON-LD playground](https://json-ld.org/playground/) to produce the canonized versions of the metadata plain text to be used to hash.
I used [this Blake2b-256](https://toolkitbay.com/tkb/tool/BLAKE2b_256) hashing tool to create the hashes.

### [CIP-100 Examples](./cip100/)

Please note, due to the base nature of CIP-100, it has very few properties/fields so it between examples things don't change too much.

#### Governance Action
- [ga.jsonld](./cip100/ga.jsonld)
- Hash: `d57d30d2d03298027fde6d1c887c65da2b98b7ddefab189dcadab9a1d6792fee`
- Github hosted: https://raw.githubusercontent.com/Ryun1/metadata/main/cip100/ga.jsonld
- IPFS hosted: https://ipfs.io/ipfs/Qmb5K1kFgNZwRbP3VbezWitpevcnNBrF3P6JcFdCFtMSrb

#### DRep Registration
- [reg.jsonld](./cip100/reg.jsonld)
- Hash: `bc88b294572f45f6b450514c17fe5fbaba492c81de3177ab21a1b4b1cb8dafd1`
- Github hosted: https://raw.githubusercontent.com/Ryun1/metadata/main/cip100/reg.jsonld
- IPFS hosted: https://ipfs.io/ipfs/QmcfdhYp2itxvjF2cTbCSDqNPZ56Q8VdYPjy5FGiHaeRTe

### [CIP-108 Examples](./cip108/)

#### Treasury Withdrawal
- [treasury-withdrawal.jsonld](./cip108/treasury-withdrawal.jsonld)
- Hash: `931f1d8cdfdc82050bd2baadfe384df8bf99b00e36cb12bfb8795beab3ac7fe5`
- Github hosted: https://raw.githubusercontent.com/Ryun1/metadata/main/cip108/treasury-withdrawal.jsonld
- IPFS hosted: https://ipfs.io/ipfs/QmdUDw7EsEyT9TCiCik1z1W6jakLhL5HWcZ87j2jCnGGYd?filename=no-confidence.jsonld

#### No Confidence
- [no-confidence.jsonld](./cip108/no-confidence.jsonld)
- Hash: `f5da6b55e1b24e657984a99b1155c307b24284472d409ab3ea8871f8ca1d3194`
- Github hosted: https://raw.githubusercontent.com/Ryun1/metadata/main/cip108/no-confidence.jsonld
- IPFS hosted: https://ipfs.io/ipfs/QmdUDw7EsEyT9TCiCik1z1W6jakLhL5HWcZ87j2jCnGGYd?filename=no-confidence.jsonld