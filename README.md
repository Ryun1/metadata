# Governance Metadata Testing

This repo contains examples of what off-chain governance metadata anchors could look like.

## Background

[CIP-1694](https://github.com/cardano-foundation/CIPs/blob/master/CIP-1694/README.md) introduces the concept of governance metadata anchors, which provide a mechanism to link off-chain metadata to on-chain governance events.

Having standards for how this off-chain metadata should look will enable rich user experiences in governance tooling.

[CIP-0100 | Governance Metadata](https://github.com/cardano-foundation/CIPs/tree/master/CIP-0100) was developed by the community to act as a base standard for all governance metadata.
This defines best practices and generic fields which can be used for anchors.

CIP-100 was designed to be expanded upon by downstream CIPs.
These CIPs will extend the property vocabulary to cater to different types ot metadata anchor.

## Examples

I used [this Blake2b-256](https://toolkitbay.com/tkb/tool/BLAKE2b_256) hashing tool to create the hashes.

I used [JSON-LD Playground](https://json-ld.org/playground/) to create canonized versions of `body` to create `author` witnesses.

I used [Ed25519 Online Tool](https://cyphr.me/ed25519_tool/ed.html) to create witnesses in `authors` field.

### [CIP-100 Examples](./cip100/)

Please note, due to the base nature of CIP-100, it has very few properties/fields so it between examples things don't change too much.

#### Governance Action

- [ga.jsonld](./cip100/ga.jsonld)
- Hash: `1805dc601b3b6fe259c646a94edb14d52534c09a0ee51e5ac502fa823b6a510c`
- Github hosted: https://raw.githubusercontent.com/Ryun1/metadata/main/cip100/ga.jsonld

#### DRep Registration

- [reg.jsonld](./cip100/reg.jsonld)
- Hash: `97d8b550056ee9e88c46784a89cd365332adc41b63fc24270780069ebd05f53a`
- Github hosted: https://raw.githubusercontent.com/Ryun1/metadata/main/cip100/reg.jsonld

### [CIP-108 Examples](./cip108/)

#### Treasury Withdrawal

- [treasury-withdrawal.jsonld](./cip108/treasury-withdrawal.jsonld)
- Hash: `633e6f25fea857662d1542921f1fa2cab5f90a9e4cb51bdae8946f823e403ea8`
- Github hosted: https://raw.githubusercontent.com/Ryun1/metadata/main/cip108/treasury-withdrawal.jsonld

#### No Confidence
- [no-confidence.jsonld](./cip108/no-confidence.jsonld)
- Hash: `f95826679a0097b5132f0af398676402e77bce0cf2d08ca7d0ffe1952d4f6872`
- Github hosted: https://raw.githubusercontent.com/Ryun1/metadata/main/cip108/no-confidence.jsonld
