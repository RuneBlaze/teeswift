import treeswift as ts
import sys
with open(sys.argv[1]) as fh:
    for l in fh:
        print(ts.read_tree_newick(l).newick())