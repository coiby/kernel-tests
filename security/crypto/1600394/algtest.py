# Derived from the Python test suite.
# Run with: scl enable rh-python36 -- python3 algtest.py

import socket

def create_alg(typ, name):
    sock = socket.socket(socket.AF_ALG, socket.SOCK_SEQPACKET, 0)
    try:
        sock.bind((typ, name))
    except FileNotFoundError as e:
        # type / algorithm is not available
        sock.close()
        raise unittest.SkipTest(str(e), typ, name)
    else:
        return sock

key = bytes.fromhex('c939cc13397c1d37de6ae0e1cb7c423c')
iv = bytes.fromhex('b3d8cc017cbb89b39e0f67e2')
plain = bytes.fromhex('c3b3c41f113a31b73d9a5cd432103069')
assoc = bytes.fromhex('24825602bd12a984e0092d3e448eda5f')
expected_tag = bytes.fromhex('0032a1dc85f1c9786925a2e71d8272dd')

taglen = len(expected_tag)
assoclen = len(assoc)

with create_alg('aead', 'gcm(aes)') as algo:
    algo.setsockopt(socket.SOL_ALG, socket.ALG_SET_KEY, key)
    algo.setsockopt(socket.SOL_ALG, socket.ALG_SET_AEAD_AUTHSIZE,
                    None, taglen)

    # send assoc, plain and tag buffer in separate steps
    op, _ = algo.accept()
    with op:
        op.sendmsg_afalg(op=socket.ALG_OP_ENCRYPT, iv=iv,
                         assoclen=assoclen, flags=socket.MSG_MORE)
        op.sendall(assoc, socket.MSG_MORE)
        op.sendall(plain)
        res = op.recv(assoclen + len(plain) + taglen)

    # now with msg
    op, _ = algo.accept()
    with op:
        msg = assoc + plain
        op.sendmsg_afalg([msg], op=socket.ALG_OP_ENCRYPT, iv=iv,
                         assoclen=assoclen)
        res = op.recv(assoclen + len(plain) + taglen)
