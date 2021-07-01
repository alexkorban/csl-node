require "./setup"
util = require "../util"

describe "util.abbrevArrays", ->
    it "abbreviates arrays", ->
        obj =
            id: 123
            items: [1, 2, 3, 4, 5, 6, 7, 8, 9, 10]
            foosa: [{a: 1}, {b: 2}, {a: 1}, {b: 2}, {a: 1}, {b: 2}]

        assert R.isArrayLike util.abbrevArrays(obj).items
        assert.equal util.abbrevArrays(obj).items[0], "#{obj.items.length} items"
        assert R.isArrayLike util.abbrevArrays(obj).foosa
        assert.equal util.abbrevArrays(obj).foosa[0], "#{obj.foosa.length} items"

    it "preserves non-array objects", ->
        obj =
            id: 123
            items: "just a string"
            none: null
            empty: []
            small: [{a: 1}, {b: 2}, {a: 1}]

        #console.log util.abbrevArrays(obj)
        assert.deepEqual util.abbrevArrays(obj), obj
