## Trust-Trade

Off-chain, centralized and trustless (\*) payment channel for high frequency
trading between two peers over a semi-trusted third party.

Very simple POC implemented as part of the Israeli Mastercoin hackathon
by Shaul Kfir (from [Bits Of Gold](https://www.bitsofgold.co.il/))
and Nadav Ivgi (from [Bitrated](https://www.bitrated.com/)).

**Not suitable for production use, at all!**
Very messy, still missing networking and some security properties, and implements an older payment
channel scheme.

A paper explaining how this works will probably be released in the future.

\* The trusted third party basically acts as a centralized replacement for (the now defunct) nSequence.
   He cannot steal funds or collude with the other party to steal funds,
   but can publish older txs or delay publication (basically, get a free binary option).

