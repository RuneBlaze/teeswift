local BRACKET = {
    ['['] = ']',
    ['{'] = '}',
    ["'"] = "'",
    ['"'] = '"',
}
local pprint = require('pprint')
if not unpack then unpack = table.unpack end

-- time to reinvent the wheel...
local deque = require('deque')

local function remove_item(array, value)
    for i, v in ipairs(array) do
        if v == value then
            array[i] = nil
        end
    end
end

local function extend(l, r)
    for _, v in ipairs(r) do
        l[#l+1] = v
    end
end

function Tree(is_rooted)
    local tree = {
        is_rooted = is_rooted,
        root = Node(),
    }

    function tree.traverse_leaves(self)
        return self.root:traverse_leaves()
    end

    function tree.traverse_preorder(self, a, b)
        return self.root:traverse_preorder(a, b)
    end

    function tree.copy(self)
        return self:extract_tree(nil, false, false)
    end

    function tree.extract_subtree(self, node)
        local r = self.root
        self.root = node
        local o = self:copy()
        self.root = r
        return o
    end

    function tree.suppress_unifurcations(self)
        local q = deque.new()
        q:push_right(self.root)
        while q:length() > 0 do
            local node = q:pop_left()
            if #node ~= 1 then
                extend(q, node)
            else -- no continue in lua
                local child = table.remove(node)
                if node:is_root() then
                    self.root = child
                    child.parent = nil
                else
                    local parent = node.parent
                    remove_item(parent, node)
                    parent:add_child(child)
                end
                if node.edge_length then
                    if child.edge_length then
                        child.edge_length = 0
                    end
                    child.edge_length = child.edge_length + node.edge_length
                end
                if child.label and node.label then
                    child.label = node.label
                end
                q:push_right(child)
            end
        end
    end

    function tree.newick(self)
        local suffix = ''
        if self.root.edge_length then
            suffix = suffix..string.format(":%s", tostring(self.root.edge_length))
        end
        if self.root.edge_params then
            suffix = suffix..string.format("[%s]", self.root.edge_length)
        end
        suffix=suffix..";"
        if self.is_rooted then
            return string.format('[&R] %s%s', self.root:newick(), suffix)
        else
            return string.format('%s%s', self.root:newick(), suffix)
        end
    end

    function tree.extract_tree(self, labels, without, suppress_unifurcations)
        -- pprint({labels, without})
        if suppress_unifurcations == nil then suppress_unifurcations = true end
        if labels and #labels > 0 then
            local nl = {}
            for _,v in ipairs(labels) do
                nl[v] = true
            end
            labels = nl
        end
        local label2leaf = {}
        local keep = {}
        for node in self:traverse_leaves() do
            label2leaf[node:newick()] = node
            if labels == nil or (without and not labels[tostring(node)]) or (not without and labels[tostring(node)]) then
                keep[node] = true
            end
        end

        -- local n = 0
        -- for node, _ in pairs(keep) do
        --     print(node)
        --     n = n + 1
        -- end
        -- print("N="..n)
        local newkeep = {}

        for node,v in pairs(keep) do
            -- print(v)
            -- print(node)
            for a in node:traverse_ancestors(false) do
                -- if not keep[a] then
                    -- print(a)
                -- end
                newkeep[a] = true
            end
        end

        for a,_ in pairs(newkeep) do
            keep[a] = true
        end
        -- print("loop ended")
        
        -- pprint(keep)

        local out = Tree()
        out.root.label = self.root.label
        out.root.edge_length = self.root.edge_length
        local q_old = deque.new()
        local q_new = deque.new()
        q_old:push_right(self.root)
        q_new:push_right(out.root)
        while q_old:length() > 0 do
            local n_old = q_old:pop_left()
            local n_new = q_new:pop_left()
            for _, c_old in ipairs(n_old) do
                if keep[c_old] then
                    local c_new = Node(tostring(c_old), c_old.edge_length)
                    n_new:add_child(c_new)
                    q_old:push_right(c_old)
                    q_new:push_right(c_new)
                end
            end
        end
        if suppress_unifurcations then
            out:suppress_unifurcations()
        end
        return out
    end

    function tree.reroot(self, node, length, branch_support)
        if length and length > 0 then
            local newnode = Node(nil, node.edge_length-length)
            node.edge_length = node.edge_length - length
            if not node:is_root() then
                local p = node.parent
                remove_item(p, node)
                p:add_child(newnode)
            end
            newnode:add_child(node)
            node = newnode
        end
        if node:is_root() then
            return
        elseif self.root.edge_length then
            -- this is weird
            local newnode = Node('ROOT')
            newnode:add_child(self.root)
            self.root = newnode
        end
        local ancestors = {}
        for a in node:traverse_ancestors(true) do
            if not a:is_root() then
                ancestors[#ancestors+1] = a
            end
        end
        for i=#ancestors,1,-1 do
            local curr = ancestors[i]
            curr.parent.edge_length = curr.edge_length
            curr.edge_length = nil
            if branch_support then
                curr.parent.label = curr.label
                curr.label = nil
            end
            remove_item(curr.parent, curr)
            curr:add_child(curr.parent)
            curr.parent = nil
        end
        self.root = node
        self.is_rooted = true
    end

    -- setmetatable(tree, {
    --     __index = function (tbl, k)
    --         return function (self, ...)
    --             tbl.root[k](self.root, unpack(arg))
    --         end
    --     end
    -- })

    return tree
end

function Node(label, edge_length)
    local node = {
        parent = nil,
        label = label,
        edge_length = edge_length,

        add_child = function (self, child)
            table.insert(self, child)
            child.parent = self
        end,
    }

    function node.is_leaf(self)
        return #self == 0
    end

    function node.is_root(self)
        return self.parent == nil
    end

    function node.resolve_polytomies(self)
        local q = deque.new()
        q:push_right(self)
        while q:length() > 0 do
            local node = q:pop_left()
            while #node > 2 do
                local c1 = table.remove(node)
                local c2 = table.remove(node)
                local nn = Node(nil, 0)
                node:add_child(nn)
                nn:add_child(c1)
                nn:add_child(c2)
            end
            for _, v in ipairs(node) do
                q:push_right(v)
            end
        end
    end

    function node.traverse_ancestors(self, include_self)
        -- local function gen()
            if include_self == nil then include_self=true end
            local c = nil
            if include_self then
                c = self
            else
                c = self.parent
            end
            return function()
                if c then
                    local p = c
                    c = c.parent
                    return p
                end
            end
            -- while c do
                -- coroutine.yield(c)
                -- c = c.parent
            -- end
            -- if 
        -- end
        -- return coroutine.wrap(gen)
    end
    
    function node.traverse_leaves(self)
        return self:traverse_preorder(true, false)
    end

    function node.traverse_preorder(self, leaves, internal)
        local function gen()
            local s = {}
            s[#s+1] = self
            while #s > 0 do
                local n = table.remove(s)
                if (leaves and n:is_leaf()) or (internal and not n:is_leaf()) then
                    coroutine.yield(n)
                end
                for _, v in ipairs(n) do
                    s[#s+1] = v
                end
            end
        end
        return coroutine.wrap(gen)
    end

    function node.contract(self)
        if self:is_root() then
            return
        end
        for _, c in ipairs(self) do
            if self.edge_length and c.edge_length then
                c.edge_length = c.edge_length + self.edge_length
            end
            self.parent:add_child(c)
        end
        remove_item(self.parent, self)
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

    setmetatable(node, {
        __tostring = function (self)
            if self.label == nil then
                return ''
            else
                return tostring(self.label)
            end
        end
    })
    return node
end

function read_tree_newick(newick)
    local t = Tree()
    local n = t.root
    local i = 1
    local parse_length = false
    local ts = newick
    while i <= #ts do
        local tsi = string.sub(ts, i, i)
        if tsi == ";" then
            if i ~= #ts or n ~= t.root then
                error("invalid newick")
            end
        elseif tsi == "(" then
            local c = Node()
            n:add_child(c)
            n = c
        elseif tsi == ")" then
            n = n.parent
        elseif tsi == "," then
            n = n.parent
            local c = Node()
            n:add_child(c)
            n = c
        elseif tsi == "[" then
            local count = 0
            local start_ind = i
            while true do
                if tsi == '[' then
                    count = count + 1
                elseif tsi == ']' then
                    count = count - 1
                    if count == 0 then
                        break
                    end
                end
            end
            n.edge_params = string.sub(start_ind + 1, i - 1)
        elseif tsi == ":" then
            parse_length = true
        elseif parse_length then
            local ls = {}
            while tsi ~= ',' and tsi ~= ')' and tsi ~= ';' and tsi ~= '[' do
                ls[#ls+1] = tsi
                i = i + 1
                tsi = string.sub(ts, i, i)
            end
            n.edge_length = tonumber(table.concat(ls, ''))
            i = i - 1
            tsi = string.sub(ts, i, i)
            parse_length = false
        else
            local label = {}
            local bracket = nil
            while bracket or BRACKET[tsi] or (tsi ~= ':' and tsi ~= ',' and tsi ~= ';' and tsi ~= ')') do
                if BRACKET[tsi] and bracket == nil then
                    bracket = tsi
                elseif bracket and tsi == BRACKET[bracket] then
                    bracket = nil
                end
                label[#label+1] = tsi
                i = i + 1
                tsi = string.sub(ts, i, i)
            end
            i = i - 1
            n.label = table.concat(label, '')
        end
        i = i + 1
    end
    return t
end