# Governance Metadata Testing

This repo contains test governance metadata, which will be present in [metadata anchors](https://github.com/cardano-foundation/CIPs/blob/729bf52030f42295b71c3edfa52b32186f7c2c01/CIP-1694/README.md?plain=1#L741-#L744).

I have based the metadata on [CIP-0100? | Governance Metadata](https://github.com/cardano-foundation/CIPs/pull/556) at commit [68b35d7](https://github.com/cardano-foundation/CIPs/pull/556/commits/68b35d7dc4268803e150abbd19eb0a653cde9c19).

I used [this Blake2b-256](https://toolkitbay.com/tkb/tool/BLAKE2b_256) hashing tool to create the hashes.

### Navigation

Each sub directory contains two files:
- `metadata.json` - This contains the raw metadata.
- `metadata-hash` - This simple file just contains a hash of the metadata.

### Motivation

- To have a tool to visually show people what metadata anchors could look like.
- To have some mock data to use during development of tooling.