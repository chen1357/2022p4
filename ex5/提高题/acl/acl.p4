/* -*- P4_16 -*- */
#include <core.p4>
#include <v1model.p4>

const bit<16> TYPE_IPV4 = 0x800;

/*************************************************************************
*********************** H E A D E R S  ***********************************
*************************************************************************/

typedef bit<9>  egressSpec_t;
typedef bit<48> macAddr_t;
typedef bit<32> ip4Addr_t;

header ethernet_t {
    macAddr_t dstAddr;
    macAddr_t srcAddr;
    bit<16>   etherType;
}

header ipv4_t {
    bit<4>    version;
    bit<4>    ihl;
    bit<8>    diffserv;
    bit<16>   totalLen;
    bit<16>   identification;
    bit<3>    flags;
    bit<13>   fragOffset;
    bit<8>    ttl;
    bit<8>    protocol;
    bit<16>   hdrChecksum;
    ip4Addr_t srcAddr;
    ip4Addr_t dstAddr;
}

header tcp_t {
    bit<16> srcPort;
    bit<16> dstPort;
    bit<32> seqNo;
    bit<32> ackNo;
    bit<4>  dataOffset;
    bit<3>  res;
    bit<3>  ecn;
    bit<6>  ctrl;
    bit<16> window;
    bit<16> checksum;
    bit<16> urgentPtr;
}

header udp_t {
    bit<16> srcPort;
    bit<16> dstPort;
    bit<16> pkt_length;
    bit<16> checksum;
}

struct metadata {
    /* empty */
}

struct headers {
    ethernet_t   ethernet;
    ipv4_t       ipv4;
    tcp_t        tcp;
    udp_t        udp;
}

/*************************************************************************
*********************** P A R S E R  ***********************************
*************************************************************************/

parser MyParser(packet_in packet,
                out headers hdr,    //out相当于输出的数据,type是headers
                inout metadata meta,//inout同时作为输入和输出值
                inout standard_metadata_t standard_metadata) {

    state start {
        transition parse_ethernet;//转移到parse_ethernet状态
    }

    state parse_ethernet {
        packet.extract(hdr.ethernet);//根据定义结构提取以太包头
        transition select(hdr.ethernet.etherType) {//根据etherType的值（协议类型）选择下一个状态，直到转移到accept
            TYPE_IPV4: parse_ipv4;  //如果是TYPE_IPV4,则转移到parse_ipv4状态（解析ip包头）
            default: accept;        //默认接受
        }
    }

    state parse_ipv4 {
        packet.extract(hdr.ipv4);
        transition select(hdr.ipv4.protocol) {
            6: parse_tcp;
            17: parse_udp;
            default: accept;
        }
    }

    state parse_tcp {
        packet.extract(hdr.tcp);
        transition accept;
    }

    state parse_udp {
        packet.extract(hdr.udp);
        transition accept;
    }

}

/*************************************************************************
************   C H E C K S U M    V E R I F I C A T I O N   *************
*************************************************************************/

control MyVerifyChecksum(inout headers hdr, inout metadata meta) {
    apply {  }
}


/*************************************************************************
**************  I N G R E S S   P R O C E S S I N G   *******************
*************************************************************************/

control MyIngress(inout headers hdr,
                  inout metadata meta,
                  inout standard_metadata_t standard_metadata) {
    action drop() {//定义丢掉 packet 的动作
        mark_to_drop(standard_metadata);//内置函数，将当前数据包标记为即将丢弃的数据包
    }

    action ipv4_forward(macAddr_t dstAddr, egressSpec_t port) {
        standard_metadata.egress_spec = port;       //设置下一跃点的出口端口
        hdr.ethernet.srcAddr = hdr.ethernet.dstAddr;//使用下一跃点的地址更新以太网目标地址
        hdr.ethernet.dstAddr = dstAddr;             //使用交换机的地址更新以太网源地址
        hdr.ipv4.ttl = hdr.ipv4.ttl - 1;            //递减 TTL
    }

    table ipv4_lpm {
        key = {//流表匹配域关键字
            hdr.ipv4.dstAddr: lpm;
        }
        actions = {//流表动作集合
            ipv4_forward;
            drop;
            NoAction;
        }
        size = 1024;//流表可以容纳最大流表项
        default_action = drop();//默认动作丢弃
    }

    /* TODO: Create a table for access control list.
       Hints: Use ipv4_lpm table as an example.
       Hints: The table should have the following specification
          key: hdr.ipv4.dstAddr (ternary), hdr.udp.dstPort (ternary)
          actions: drop, NoAction
          size: 1024
          default action: NoAction
       Hints: Do not forget to add two rules to s1-acl.json. One rule should
          drop packets with UDP port 80, by specifying {"hdr.udp.dstPort":
          [80, 65535]} as "match". The other rule should drop packets with
          IPv4 address 10.0.1.4, by specifing {"hdr.ipv4.dstAddr": ["10.0.1.4",
          4294967295]} as "match".
       Notes: The priority field must be set to a non-zero value 
              if the match key includes a ternary match.
     */
    table acl {
        key = {//流表匹配域关键字
            hdr.ipv4.dstAddr: ternary;//三元匹配
            hdr.udp.dstPort: ternary;//三元匹配
        }
        actions = {//流表动作集合
            drop;//丢弃动作
            NoAction;//无动作
        }
        size = 1024;//流表可以容纳最大流表项
        default_action = NoAction();//默认动作丢弃
    }

    apply {
        if (hdr.ipv4.isValid()) {
            ipv4_lpm.apply();
            /* TODO: add your table to the control flow */
            acl.apply();
        }

    }
}

/*************************************************************************
****************  E G R E S S   P R O C E S S I N G   *******************
*************************************************************************/

control MyEgress(inout headers hdr,
                 inout metadata meta,
                 inout standard_metadata_t standard_metadata) {
    apply {  }
}

/*************************************************************************
*************   C H E C K S U M    C O M P U T A T I O N   **************
*************************************************************************/

control MyComputeChecksum(inout headers  hdr, inout metadata meta) {
     apply {
	update_checksum(
	    hdr.ipv4.isValid(),
            { hdr.ipv4.version,
	      hdr.ipv4.ihl,
              hdr.ipv4.diffserv,
              hdr.ipv4.totalLen,
              hdr.ipv4.identification,
              hdr.ipv4.flags,
              hdr.ipv4.fragOffset,
              hdr.ipv4.ttl,
              hdr.ipv4.protocol,
              hdr.ipv4.srcAddr,
              hdr.ipv4.dstAddr },
            hdr.ipv4.hdrChecksum,
            HashAlgorithm.csum16);
    }
}

/*************************************************************************
***********************  D E P A R S E R  *******************************
*************************************************************************/

control MyDeparser(packet_out packet, in headers hdr) {
    apply {
        packet.emit(hdr.ethernet);
        packet.emit(hdr.ipv4);
        packet.emit(hdr.tcp);
        packet.emit(hdr.udp);
    }
}

/*************************************************************************
***********************  S W I T C H  *******************************
*************************************************************************/

V1Switch(
MyParser(),
MyVerifyChecksum(),
MyIngress(),
MyEgress(),
MyComputeChecksum(),
MyDeparser()
) main;
