module dca::trade_policy {
    // === Imports ===

    use std::type_name::{Self, TypeName};

    use sui::clock::Clock;
    use sui::coin::{Self, Coin};
    use sui::vec_set::{Self, VecSet};
    use sui::transfer::{transfer, share_object};

    use dca::dca::{DCA};

    // === Errors ===

    const EInvalidDcaAddress: u64 = 0;
    const ERuleAlreadyAdded: u64 = 1;
    const EMustHaveARule: u64 = 2;
    const EInvalidRule: u64 = 3;

    // === Structs ===

    public struct Admin has key, store {
        id: UID
    }

    public struct TradePolicy has key {
        id: UID,
        whitelist: VecSet<TypeName>
    }

    #[allow(lint(coin_field))]
    public struct Request<phantom Output> {
        dca_address: address,
        rule: Option<TypeName>,
        whitelist: VecSet<TypeName>,
        output: Coin<Output>,
    }

    // === Public-Mutative Functions ===

    fun init(ctx: &mut TxContext) {
        let trade_policy = TradePolicy {
            id: object::new(ctx),
            whitelist: vec_set::empty()
        };

        share_object(trade_policy);
        transfer(Admin { id: object::new(ctx) }, ctx.sender());
    }

    public fun request<Input, Output>(
        self: &TradePolicy,
        dca: &mut DCA<Input, Output>,
        ctx: &mut TxContext
    ): (Request<Output>, Coin<Input>) {
        let request = Request {
            dca_address: object::id_address(dca),
            rule: option::none(),
            whitelist: self.whitelist,
            output: coin::zero(ctx),
        };

        (request, dca.take(ctx))
        }

        public fun add<Witness: drop, Output>(request: &mut Request<Output>, _: Witness, output: Coin<Output>) {
        assert!(request.rule.is_none(), ERuleAlreadyAdded);

        request.rule = option::some(type_name::get<Witness>());
        request.output.join(output);
    }

    public fun confirm<Input, Output>(
        dca: &mut DCA<Input, Output>,
        clock: &Clock,
        request: Request<Output>
    ) {
        let Request {
            dca_address,
            rule,
            whitelist,
            output
        } = request;

        assert!(object::id_address(dca) == dca_address, EInvalidDcaAddress);
        assert!(rule.is_some(), EMustHaveARule);
        assert!(whitelist.contains(&rule.destroy_some()), EInvalidRule);

        dca.resolve(clock, output);
    }

    // === Public-View Functions ===

    public fun whitelist(self: &TradePolicy): vector<TypeName> {
        self.whitelist.into_keys()
    }

    public fun dca_address<Output>(request: &Request<Output>): address {
        request.dca_address
    }

    public fun rule<Output>(request: &Request<Output>): Option<TypeName> {
        request.rule
    }

    public fun output<Output>(request: &Request<Output>): u64 {
        request.output.value()
    }

    // === Admin Functions ===

    public fun approve<Witness: drop>(_: &Admin, self: &mut TradePolicy) {
        self.whitelist.insert(type_name::get<Witness>());
    }

    public fun disapprove<Witness: drop>(_: &Admin, self: &mut TradePolicy) {
        self.whitelist.remove(&type_name::get<Witness>());
    }

    // === Test Functions ===

    #[test_only]
    public fun init_for_testing(ctx: &mut TxContext) {
        init(ctx);
    }
}