package org.perl6.nqp.truffle.nodes.expression;
import com.oracle.truffle.api.frame.VirtualFrame;
import com.oracle.truffle.api.nodes.NodeInfo;
import org.perl6.nqp.truffle.nodes.NQPNode;
import org.perl6.nqp.truffle.nodes.NQPObjNode;
import org.perl6.nqp.truffle.NQPScope;
import org.perl6.nqp.dsl.Deserializer;

@NodeInfo(shortName = "BVal")
public final class NQPBValNode extends NQPObjNode {
    final NQPScope scope;
    final String cuid;

    @Deserializer
    public NQPBValNode(NQPScope scope, String cuid) {
        this.scope = scope;
        this.cuid = cuid;
    }

    @Override
    public Object execute(VirtualFrame frame) {
        return scope.getCuid(cuid);
    }
}