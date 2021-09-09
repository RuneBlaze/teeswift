function Node(label, edgelen)
    local node = {
        parent = nil,
        label = label,
        edge_length = nil,


        add_child = function (self, child)
            table.insert(self, child)
        end,
    }

    function node.is_leaf(self)
        return #self == 0
    end

    function node.traverse_postorder(self, leaves, internal)
        local function gen()
            if leaves == nil then leaves = true end
            if internal == nil then internal = true end

            local s1 = {}
            local s2 = {}
            s1[#s1+1] = self
            while #s1 > 0 do
                local n = table.remove(s1)
                s2[#s2+1] = n
                for _, v in ipairs(n) do
                    s1[#s1+1] = v
                end
            end
            while #s2 > 0 do
                local n = table.remove(s2)
                if (leaves and n:is_leaf()) or (internal and not n:is_leaf()) then
                    coroutine.yield(n)
                end
            end
        end
        return coroutine.wrap(gen)
    end

    function node.newick(self)
        local node2str = {}
        for n in self:traverse_postorder() do
            if #n == 0 then
                if not n.label then
                    node2str[n] = ''
                else
                    node2str[n] = tostring(n.label)
                end
            else
                local out = {'('}
                for _, c in ipairs(n) do
                    out[#out+1] = node2str[c]
                    if c.edge_length then
                        out[#out+1] = ':'..tostring(c.edge_length)
                    end
                    if c.edge_params then
                        out[#out+1] = '['..tostring(c.edge_params)..']'
                    end
                    out[#out+1] = ','
                    node2str[c] = nil
                end
                table.remove(out)
                out[#out+1] = ')'
                if n.label then
                    out[#out+1] = tostring(n.label)
                end
                node2str[n] = table.concat(out,'')
            end
        end
        return node2str[self]
    end
    return node
end