local data_text = Proto("data_as_text", "Data as Text")
local f_text = ProtoField.string("data_as_text.value", "Data Text")
data_text.fields = {f_text}

local f_data = Field.new("data.data")

function data_text.dissector(tvb, pinfo, tree)
    local data_field = f_data()
    if data_field then
        local raw = data_field.range
        tree:add(f_text, raw, raw:string())
    end
end

register_postdissector(data_text)