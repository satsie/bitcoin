#!/usr/bin/env python3
# Copyright (c) 2019-2022 The Bitcoin Core developers
# Distributed under the MIT software license, see the accompanying
# file COPYING or http://www.opensource.org/licenses/mit-license.php.

""" Test node eviction logic for outbound peers

When the number of peers has reached the limit of maximum connections,
the next outbound peer connection will trigger the eviction mechanism.
"""

from test_framework.blocktools import (
    create_block,
    create_coinbase,
)

from test_framework.p2p import P2PDataStore
from test_framework.test_framework import BitcoinTestFramework
from test_framework.util import assert_equal, p2p_port
from test_framework.messages import msg_headers, CBlockHeader

class P2PEvictOutbound(BitcoinTestFramework):
    def set_test_params(self):
        self.setup_clean_chain = True
        self.num_nodes = 1

    # This test could use a better name. The idea is to check that the peer that recently sent a block doesn't get evicted.
    # Eviction seems like the only way to test that the value for received_new_header is correct
    def test_last_block_announcement_eviction(self):
        self.log.info('Check that received_new_header is updated correctly for peers who recently sent blocks, thus preventing eviction')

        # Restart to disconnect peers and load default extra_args
        self.restart_node(0)

        unprotected_peers = []
        protected_peers = set() # peers that we expect to be protected from eviction
        node = self.nodes[0]

        current_peer_index = -1

        # First create 7 full-relay peers
        for _ in range (7):
            current_peer_index += 1
            unprotected_peer = node.add_outbound_p2p_connection(P2PDataStore(), p2p_idx=current_peer_index, connection_type="outbound-full-relay")
            unprotected_peers.append(unprotected_peer)

        self.log.debug("Created 7 peers. Number of outbound connections: {}".format(len(node.p2ps)))
        self.log.debug("current_peer_index = {}".format(current_peer_index))

        self.log.info('Creating one more peer and protecting it from eviction by having it send a new block')
        current_peer_index += 1
        block_peer = node.add_outbound_p2p_connection(P2PDataStore(), p2p_idx=current_peer_index, connection_type="outbound-full-relay")
        block_peer.sync_with_ping

        # add the peer to the list of protected peers
        protected_peers.add(current_peer_index)
        self.log.debug("peer {} is protected".format(current_peer_index))

        # Gather some details about the current best block so we can create a new one
        best_block = node.getbestblockhash()
        tip = int(best_block, 16)
        best_block_time = node.getblock(best_block)['time']

        # Create the new block and send it
        new_block = create_block(tip, create_coinbase(node.getblockcount() + 1), best_block_time + 1)
        new_block.solve()
        block_peer.send_blocks_and_test([new_block], node, success=True)

        # Have all the other nodes send headers for the same block. received_new_header should not update for these nodes
        # and they should remain candidates for eviction
        self.log.info("Having the rest of the {} peers send the same block".format(len(unprotected_peers)))

        i = 0
        for _ in unprotected_peers:
            self.log.info("unprotected peer {} sending a block".format(i))
            _.send_message(msg_headers([CBlockHeader(block) for block in [new_block]]))
            self.log.info("peer {} sent block. iterating again".format(i))
            i = i + 1

        # Add an extra outbound connection using the test only addconnection RPC
        current_peer_index += 1
        ip_port = "127.0.0.1:{}".format(p2p_port(current_peer_index))
        # TODO I know I'm not invoking this quite right
        # test_framework.authproxy.JSONRPCException: Error: Already at capacity for specified connection type. (-34)
        #node.addconnection('%s:%d' % ('127.0.0.1', 9), 'outbound-full-relay')

        # other option: addnode RPC. This doesn't seem to do anything so I'm not sure if I'm calling it correctly.
        node.addnode(node=ip_port, command='add')

        # Check to see which node was evicted
        evicted_peers = []
        for i in range (len(node.p2ps)):
            if not node.p2ps[i].is_connected:
                evicted_peers.append(i)

        # TODO assertions on the peer that was evicted/peer that wasn't evicted
        self.log.info("Test that one peer was evicted")
        self.log.info("{} evicted peer: {}".format(len(evicted_peers), set(evicted_peers)))
        assert_equal(len(evicted_peers), 1)

        self.log.info("Test that no peer expected to be protected was evicted")
        self.log.info("{} protected peers: {}".format(len(protected_peers), protected_peers))
        assert evicted_peers[0] not in protected_peers

    def run_test(self):
        self.test_last_block_announcement_eviction()

if __name__ == '__main__':
    P2PEvictOutbound().main()
