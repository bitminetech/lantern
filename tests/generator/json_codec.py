"""Cases of lantern_json_encode (docs/reference/beacon-api.md), made with the pinned spec.

The values come from get_random_ssz_object of the pinned spec's test helpers, for every container
type of the fork's spec module: in minimal the modes zero, one, random and max, lists of at most 4
items and byte lists of at most 64 bytes; in mainnet the mode zero only, as its states are large.
The JSON is written here by the rules of lantern_json_encode, apart from the assembly: a uint as a
decimal string, Boolean as true or false, byte and bit strings as 0x and lower case hex (a bit list
with its delimiter bit), lists and vectors as arrays, containers as objects of the spec's field
names in order, no white space.

cases(fork, preset) yields (name, parts): "type", the container's name; "ssz", the value's SSZ
bytes; "json", its JSON.
"""

from random import Random

from ssz.bitfields import BitList, BitVector
from ssz.boolean import Boolean
from ssz.byte_arrays import ByteList, ByteVector
from ssz.collections import List, Vector
from ssz.container import Container
from ssz.uint import BaseUint

from eth_consensus_specs.debug.random_value import RandomizationMode, get_random_ssz_object
from p2p import module

MODES = {"minimal": ("zero", "one_count", "random", "max"), "mainnet": ("zero",)}


def to_json(value):
    if isinstance(value, Boolean):
        return "true" if value else "false"
    if isinstance(value, BaseUint):
        return '"%d"' % int(value)
    if isinstance(value, (BitList, BitVector)):
        return '"0x' + bytes(value.encode_bytes()).hex() + '"'
    if isinstance(value, (ByteList, ByteVector)):
        return '"0x' + bytes(value).hex() + '"'
    if isinstance(value, (List, Vector)):
        return "[" + ",".join(to_json(item) for item in value) + "]"
    if isinstance(value, Container):
        return "{" + ",".join('"%s":%s' % (name, to_json(getattr(value, name))) for name in type(value).model_fields) + "}"
    raise TypeError(type(value))


def containers(spec):
    for name in sorted(dir(spec)):
        t = getattr(spec, name)
        if isinstance(t, type) and issubclass(t, Container) and t is not Container and t.__name__ == name:
            yield name, t


def cases(fork, preset):
    spec = module(fork, preset)
    for name, t in containers(spec):
        for mode in MODES[preset]:
            rng = Random(f"{fork}-{name}-{mode}")
            try:
                value = get_random_ssz_object(rng, t, 64, 4, getattr(RandomizationMode, "mode_" + mode), False)
                text = to_json(value)
            except TypeError:
                break  # a kind outside phase0 to fulu, such as a progressive type: no case
            yield f"{name}_{mode}", {"type": name.encode(), "ssz": bytes(value.encode_bytes()), "json": text.encode()}
