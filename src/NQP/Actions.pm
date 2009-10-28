class NQP::Actions is HLL::Actions;

our @BLOCK;

sub INIT() {
    our @BLOCK := Q:PIR { %r = new ['ResizablePMCArray'] };
    # These will eventually go in NQP::Grammar.
    NQP::Grammar.O(':prec<y=>, :assoc<unary>', '%methodop');
    NQP::Grammar.O(':prec<x=>, :assoc<unary>', '%autoincrement');
    NQP::Grammar.O(':prec<w=>, :assoc<left>',  '%exponentiation');
    NQP::Grammar.O(':prec<v=>, :assoc<unary>', '%symbolic_unary');
    NQP::Grammar.O(':prec<u=>, :assoc<left>',  '%multiplicative');
    NQP::Grammar.O(':prec<t=>, :assoc<left>',  '%additive');
    NQP::Grammar.O(':prec<r=>, :assoc<left>',  '%concatenation'); 
    NQP::Grammar.O(':prec<m=>, :assoc<left>',  '%relational');
    NQP::Grammar.O(':prec<l=>, :assoc<left>',  '%tight_and');
    NQP::Grammar.O(':prec<k=>, :assoc<left>',  '%tight_or');
    NQP::Grammar.O(':prec<j=>, :assoc<right>', '%conditional');
    NQP::Grammar.O(':prec<i=>, :assoc<right>', '%assignment');
    NQP::Grammar.O(':prec<g=>, :assoc<list>, :nextterm<nulltermish>',  '%comma');
    NQP::Grammar.O(':prec<f=>, :assoc<list>',  '%list_infix');
}

sub xblock_immediate($xblock) {
    $xblock[1] := block_immediate($xblock[1]);
    $xblock;
}

sub block_immediate($block) {
    $block.blocktype('immediate');
    unless $block.symtable() {
        my $stmts := PAST::Stmts.new( :node($block) );
        for $block.list { $stmts.push($_); }
        $block := $stmts;
    }
    $block;
}

sub sigiltype($sigil) {
    $sigil eq '%' 
    ?? 'Hash' 
    !! ($sigil eq '@' ?? 'ResizablePMCArray' !! 'Undef');
}

method TOP($/) { make $<comp_unit>.ast; }

method deflongname($/) {
    if $<sym> { make ~$<identifier> ~ ':sym<' ~ ~$<sym>[0] ~ '>'; }
}

method comp_unit($/) {
    my $past := $<statementlist>.ast;
    my $BLOCK := @BLOCK.shift;
    $BLOCK.push($past);
    $BLOCK.node($/);
    make $BLOCK;
}

method statementlist($/) {
    my $past := PAST::Stmts.new( :node($/) );
    if $<statement> {
        for $<statement> { 
            my $ast := $_.ast;
            if $ast.isa(PAST::Block) && !$ast.blocktype {
                $ast := block_immediate($ast);
            }
            $past.push( $ast ); 
        }
    }
    make $past;
}

method statement($/) { 
    my $past;
    if $<EXPR> { $past := $<EXPR>.ast; }
    elsif $<statement_control> { $past := $<statement_control>.ast; }
    else { $past := 0; }
    make $past;
}

method xblock($/) {
    make PAST::Op.new( $<EXPR>.ast, $<pblock>.ast, :pasttype('if'), :node($/) );
}

method pblock($/) {
    make $<blockoid>.ast;
}

method blockoid($/) {
    my $past := $<statementlist>.ast;
    my $BLOCK := @BLOCK.shift;
    $BLOCK.push($past);
    $BLOCK.node($/);
    make $BLOCK;
}

method newpad($/) {
    our @BLOCK;
    @BLOCK.unshift( PAST::Block.new( PAST::Stmts.new() ) );
}

## Statement control

method statement_control:sym<if>($/) {
    my $count := +$<xblock> - 1;
    my $past := xblock_immediate( $<xblock>[$count].ast );
    if $<else> {
        $past.push( block_immediate( $<else>[0].ast ) );
    }
    # build if/then/elsif structure
    while $count > 0 {
        $count--;
        my $else := $past;
        $past := xblock_immediate( $<xblock>[$count].ast );
        $past.push($else);
    }
    make $past;
}

method statement_control:sym<unless>($/) {
    my $past := xblock_immediate( $<xblock>.ast );
    $past.pasttype('unless');
    make $past;
}

method statement_control:sym<while>($/) {
    my $past := xblock_immediate( $<xblock>.ast );
    $past.pasttype(~$<sym>);
    make $past;
}

method statement_control:sym<repeat>($/) {
    my $pasttype := 'repeat_' ~ ~$<wu>;
    my $past;
    if $<xblock> { 
        $past := xblock_immediate( $<xblock>.ast );
        $past.pasttype($pasttype);
    }
    else {
        $past := PAST::Op.new( $<EXPR>.ast, block_immediate( $<pblock>.ast ),
                               :pasttype($pasttype), :node($/) );
    }
    make $past;
}

method statement_control:sym<for>($/) {
    my $past := $<xblock>.ast;
    $past.pasttype('for');
    my $block := $past[1];
    $block[0].push( PAST::Var.new( :name('$_'), :scope('parameter') ) );
    $block.symbol('$_', :scope('lexical') );
    $block.arity(1);
    $block.blocktype('immediate');
    make $past;
}

method statement_control:sym<return>($/) {
    make PAST::Op.new( $<EXPR>.ast, :pasttype('return'), :node($/) );
}

method statement_control:sym<make>($/) {
    make PAST::Op.new(
             PAST::Var.new( :name('$/'), :scope('contextual') ),
             $<EXPR>.ast,
             :pasttype('callmethod'),
             :name('!make'),
             :node($/)
    );
}

## Terms

method noun:sym<colonpair>($/)          { make $<colonpair>.ast; }
method noun:sym<variable>($/)           { make $<variable>.ast; }
method noun:sym<package_declarator>($/) { make $<package_declarator>.ast; }
method noun:sym<scope_declarator>($/)   { make $<scope_declarator>.ast; }
method noun:sym<routine_declarator>($/) { make $<routine_declarator>.ast; }
method noun:sym<regex_declarator>($/)   { make $<regex_declarator>.ast; }

method colonpair($/) {
    my $past := $<circumfix> 
                ?? $<circumfix>[0].ast 
                !! PAST::Val.new( :value( !$<not> ) );
    $past.named( ~$<identifier> );
    make $past;
}

method variable($/) {
    my $past;
    if $<postcircumfix> {
        $past := $<postcircumfix>.ast;
        $past.unshift( PAST::Var.new( :name('$/') ) );
    }
    else {
        $past := PAST::Var.new( :name(~$/) );
        if $<twigil> && $<twigil>[0] eq '*' { 
            $past.scope('contextual'); 
            $past.viviself( PAST::Op.new( 'Contextual ' ~ ~$/ ~ ' not found', 
                                          :pirop('die') )
            );
        }
    }
    make $past;
}

method package_declarator:sym<module>($/) { make $<package_def>.ast; }
method package_declarator:sym<class>($/) {
    my $classinit :=
        PAST::Op.new(
            PAST::Op.new( 
                :inline( '    %r = get_root_global ["parrot"], "P6metaclass"')
            ),
            ~$<package_def><name>,
            :name('new_class'),
            :pasttype('callmethod')
        );
    my $parent := ~$<package_def><parent>[0]
                  || ($<sym> eq 'grammar' ?? 'Regex::Cursor' !! '');
    if $parent {
        $classinit.push( PAST::Val.new( :value($parent), :named('parent') ) );
    }
    @BLOCK[0].loadinit.push($classinit);
    make $<package_def>.ast;
}

method package_def($/) {
    my $past := $<pblock> ?? $<pblock>.ast !! $<comp_unit>.ast;
    $past.namespace( $<name><identifier> );
    $past.blocktype('immediate');
    make $past;
}

method scope_declarator:sym<my>($/) { make $<scoped>.ast; }
method scope_declarator:sym<our>($/) {
    my $past := $<scoped>.ast;
    @BLOCK[0].symbol( $past.name, :scope('package') );
    $past.scope('package');

    # If we're modifying the scope of a block, then eliminate the
    # variable assignment and just return the (named) block itself.
    if $past<XXXroutine> {
        $past := $past.viviself;
        $past.nsentry($past.name);
    }

    make $past;
}

method scoped($/) {
    make $<routine_declarator>
         ?? $<routine_declarator>.ast
         !! $<variable_declarator>.ast;
}

method variable_declarator($/) {
    my $past := $<variable>.ast;
    my $name := $past.name;
    if @BLOCK[0].symbol($name) {
        $/.CURSOR.panic("Redeclaration of symbol ", $name);
    }
    $past.scope('lexical');
    $past.isdecl(1);
    my $sigil := $<variable><sigil>;
    $past.viviself( sigiltype($sigil) );
    @BLOCK[0].symbol( $name, :scope('lexical') );
    make $past;
}

method routine_declarator:sym<sub>($/) { make $<routine_def>.ast; }
method routine_declarator:sym<method>($/) {
    my $past := $<routine_def>.ast;
    if $past.isa(PAST::Var) { $past := $past.viviself(); }
    $past.blocktype('method');
    $past[0].unshift( PAST::Op.new( :inline('    .lex "self", self') ) );
    $past.symbol('self', :scope('lexical') );
    make $past;
}

method routine_def($/) {
    my $past := $<blockoid>.ast;
    $past.blocktype('declaration');
    $past.control('return_pir');
    if $<deflongname> {
        my $name := ~$<deflongname>[0].ast;
        $past.name($name);
        $past := PAST::Var.new( :name($name), :isdecl(1), :viviself($past),
                     :scope('lexical') );
        $past<XXXroutine> := 1;
        @BLOCK[0].symbol( $name, :scope('lexical') );
    }
    make $past;
}

method signature($/) {
    my $BLOCKINIT := @BLOCK[0][0];
    for $<parameter> { $BLOCKINIT.push($_.ast); }
}

method parameter($/) { 
    my $quant := $<quant>;
    my $past;
    if $<named_param> {
        $past := $<named_param>.ast;
        if $quant ne '!' { 
            $past.viviself( sigiltype($<named_param><param_var><sigil>) );
        }
    }
    else {
        $past := $<param_var>.ast;
        if $quant eq '*' {
            $past.slurpy(1);
            $past.named( $<param_var><sigil> eq '%' );
        }
        elsif $quant eq '?' {
            $past.viviself( sigiltype($<param_var><sigil>) );
        }
    }
    if $<default_value> { 
        if $quant eq '*' { 
            $/.CURSOR.panic("Can't put default on slurpy parameter");
        }
        if $quant eq '!' { 
            $/.CURSOR.panic("Can't put default on required parameter");
        }
        $past.viviself( $<default_value>[0]<EXPR>.ast ); 
    }
    make $past; 
}

method param_var($/) {
    my $name := ~$/;
    my $past :=  PAST::Var.new( :name($name), :scope('parameter'), 
                                :isdecl(1), :node($/) );
    @BLOCK[0].symbol($name, :scope('lexical') );
    make $past;
}

method named_param($/) {
    my $past := $<param_var>.ast;
    $past.named( ~$<param_var><name> );
    make $past;
}

method regex_declarator($/, $key?) {
    my @MODIFIERS := Q:PIR {
        %r = get_hll_global ['Regex';'P6Regex';'Actions'], '@MODIFIERS'
    };
    my $name := ~$<deflongname>.ast;
    my $past;
    if $key eq 'open' {
        my %h;
        if $<sym> eq 'token' { %h<r> := 1; }
        if $<sym> eq 'rule'  { %h<r> := 1;  %h<s> := 1; }
        @MODIFIERS.unshift(%h);
        Q:PIR {
            $P0 = find_lex '$name'
            set_hll_global ['Regex';'P6Regex';'Actions'], '$REGEXNAME', $P0
        };
        return 0;
    }
    elsif $<proto> {
        $past :=
            PAST::Stmts.new(
                PAST::Block.new( :name($name),
                    PAST::Op.new(
                        PAST::Var.new( :name('self'), :scope('register') ),
                        $name,
                        :name('!protoregex'),
                        :pasttype('callmethod'),
                    ),
                    :blocktype('method'),
                    :lexical(0),
                    :node($/)
                ),
                PAST::Block.new( :name('!PREFIX__' ~ $name),
                    PAST::Op.new(
                        PAST::Var.new( :name('self'), :scope('register') ),
                        $name,
                        :name('!PREFIX__!protoregex'),
                        :pasttype('callmethod'),
                    ),
                    :blocktype('method'),
                    :lexical(0),
                    :node($/)
                )
            );
    }
    else {
        my $rpast := $<p6regex_nibbler>.ast;
        my %capnames := Regex::P6Regex::Actions::capnames($rpast, 0);
        %capnames{''} := 0;
        $rpast := PAST::Regex.new(
                     $rpast,
                     PAST::Regex.new( :pasttype('pass') ),
                     :pasttype('concat'),
                     :capnames(%capnames)
        );
        $past := @BLOCK.shift;
        $past.blocktype('method');
        $past.name($name);
        $past.push($rpast);
        @MODIFIERS.shift;
    }
    make $past;
}


method dotty($/) {
    my $past := $<args> ?? $<args>[0].ast !! PAST::Op.new( :node($/) );
    $past.name( ~$<identifier> );
    $past.pasttype('callmethod');
    make $past;
}

## Terms

method term:sym<self>($/) {
    make PAST::Var.new( :name('self') );
}

method term:sym<identifier>($/) {
    my $past := $<args>.ast;
    $past.name(~$<identifier>);
    make $past;
}

method term:sym<name>($/) {
    my $ns := $<name><identifier>;
    $ns := Q:PIR { 
               $P0 = find_lex '$ns'
               %r = clone $P0
           };
    my $name := $ns.pop;
    my $var := 
        PAST::Var.new( :name(~$name), :namespace($ns), :scope('package') );
    my $past := $var;
    if $<args> {
        $past := $<args>[0].ast;
        $past.unshift($var);
    }
    make $past;
}

method term:sym<PIR::op>($/) {
    my $past := $<args> ?? $<args>[0].ast !! PAST::Op.new( :node($/) );
    my $pirop := ~$<op>;
    $pirop := Q:PIR {
        $P0 = find_lex '$pirop'
        $S0 = $P0
        $P0 = split '__', $S0
        $S0 = join ' ', $P0
        %r = box $S0
    };
    $past.pirop($pirop);
    $past.pasttype('pirop');
    make $past;
}

method args($/) { make $<arglist>.ast; }

method arglist($/) {
    my $past := PAST::Op.new( :pasttype('call'), :node($/) );
    if $<EXPR> {
        my $expr := $<EXPR>.ast;
        if $expr.name eq 'infix:<,>' {
            for $expr.list { $past.push($_); }
        }
        else { $past.push($expr); }
    }
    make $past;
}


method term:sym<value>($/) { make $<value>.ast; }

method circumfix:sym<( )>($/) { make $<EXPR>.ast; }

method circumfix:sym<ang>($/) { make $<quote_EXPR>.ast; }

method circumfix:sym<{ }>($/) { make $<pblock>.ast; }

method postcircumfix:sym<[ ]>($/) {
    make PAST::Var.new( $<EXPR>.ast , :scope('keyed_int'),
                        :viviself('Undef'),
                        :vivibase('ResizablePMCArray') );
}

method postcircumfix:sym<{ }>($/) {
    make PAST::Var.new( $<EXPR>.ast , :scope('keyed'),
                        :viviself('Undef'),
                        :vivibase('Hash') );
}

method postcircumfix:sym<ang>($/) {
    make PAST::Var.new( $<quote_EXPR>.ast, :scope('keyed'),
                        :viviself('Undef'),
                        :vivibase('Hash') );
}

method value($/) {
    my $past := $<quote>
                ?? $<quote>.ast
                !! PAST::Val.new( :value($<integer>.ast) );
    make $past;
}


method quote:sym<apos>($/) { make $<quote_EXPR>.ast; }
method quote:sym<dblq>($/) { make $<quote_EXPR>.ast; }
method quote:sym<qq>($/)   { make $<quote_EXPR>.ast; }
method quote:sym<q>($/)    { make $<quote_EXPR>.ast; }
method quote:sym<Q>($/)    { make $<quote_EXPR>.ast; }
method quote:sym<Q:PIR>($/) {
    make PAST::Op.new( :inline( $<quote_EXPR>.ast.value ),
                       :pasttype('inline'),
                       :node($/) );
}

## Operators

method nulltermish($/) {
    make $<noun> ?? $<noun>.ast !! 0;
}

method postfix:sym<.>($/) { make $<dotty>.ast; }

method postfix:sym<++>($/) {
    make PAST::Op.new( :name('postfix:<++>'),
                       :inline('    clone %r, %0', '    inc %0'),
                       :pasttype('inline') );
}

method postfix:sym<-->($/) {
    make PAST::Op.new( :name('postfix:<-->'),
                       :inline('    clone %r, %0', '    dec %0'),
                       :pasttype('inline') );
}

