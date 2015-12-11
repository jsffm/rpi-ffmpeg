#define ALTCABAC_VER 1
#include "cabac_functions.h"

#define I(x) (uint32_t)((0x10000000000ULL / (uint64_t)(x)) + 1ULL)

const uint32_t alt1cabac_inv_range[256] __attribute__((aligned(256))) = {
                                                    0,      I(257), I(258), I(259),
    I(260), I(261), I(262), I(263), I(264), I(265), I(266), I(267), I(268), I(269),
    I(270), I(271), I(272), I(273), I(274), I(275), I(276), I(277), I(278), I(279),
    I(280), I(281), I(282), I(283), I(284), I(285), I(286), I(287), I(288), I(289),
    I(290), I(291), I(292), I(293), I(294), I(295), I(296), I(297), I(298), I(299),
    I(300), I(301), I(302), I(303), I(304), I(305), I(306), I(307), I(308), I(309),
    I(310), I(311), I(312), I(313), I(314), I(315), I(316), I(317), I(318), I(319),
    I(320), I(321), I(322), I(323), I(324), I(325), I(326), I(327), I(328), I(329),
    I(330), I(331), I(332), I(333), I(334), I(335), I(336), I(337), I(338), I(339),
    I(340), I(341), I(342), I(343), I(344), I(345), I(346), I(347), I(348), I(349),
    I(350), I(351), I(352), I(353), I(354), I(355), I(356), I(357), I(358), I(359),
    I(360), I(361), I(362), I(363), I(364), I(365), I(366), I(367), I(368), I(369),
    I(370), I(371), I(372), I(373), I(374), I(375), I(376), I(377), I(378), I(379),
    I(380), I(381), I(382), I(383), I(384), I(385), I(386), I(387), I(388), I(389),
    I(390), I(391), I(392), I(393), I(394), I(395), I(396), I(397), I(398), I(399),
    I(400), I(401), I(402), I(403), I(404), I(405), I(406), I(407), I(408), I(409),
    I(410), I(411), I(412), I(413), I(414), I(415), I(416), I(417), I(418), I(419),
    I(420), I(421), I(422), I(423), I(424), I(425), I(426), I(427), I(428), I(429),
    I(430), I(431), I(432), I(433), I(434), I(435), I(436), I(437), I(438), I(439),
    I(440), I(441), I(442), I(443), I(444), I(445), I(446), I(447), I(448), I(449),
    I(450), I(451), I(452), I(453), I(454), I(455), I(456), I(457), I(458), I(459),
    I(460), I(461), I(462), I(463), I(464), I(465), I(466), I(467), I(468), I(469),
    I(470), I(471), I(472), I(473), I(474), I(475), I(476), I(477), I(478), I(479),
    I(480), I(481), I(482), I(483), I(484), I(485), I(486), I(487), I(488), I(489),
    I(490), I(491), I(492), I(493), I(494), I(495), I(496), I(497), I(498), I(499),
    I(500), I(501), I(502), I(503), I(504), I(505), I(506), I(507), I(508), I(509),
    I(510), I(511)
};
#undef I

#define P(x,y) (((x) << 10) | ((y) << 2) | 0x100), (((x) << 10) | ((y) << 2) | 0x203)

#define X(x,y) (((x) << 10) | ((y) << 2) | 0x300), (((x) << 10) | ((y) << 2) | 0x003)

const uint16_t alt1cabac_cabac_transIdx[256] __attribute__((aligned(256))) =
{
	X(0,1), P(0,2), P(1,3), P(2,4), P(2,5), P(4,6), P(4,7), P(5,8),
	P(6,9), P(7,10), P(8,11), P(9,12), P(9,13), P(11,14), P(11,15), P(12,16),
	P(13,17), P(13,18), P(15,19), P(15,20), P(16,21), P(16,22), P(18,23), P(18,24),
	P(19,25), P(19,26), P(21,27), P(21,28), P(22,29), P(22,30), P(23,31), P(24,32),
	P(24,33), P(25,34), P(26,35), P(26,36), P(27,37), P(27,38), P(28,39), P(29,40),
	P(29,41), P(30,42), P(30,43), P(30,44), P(31,45), P(32,46), P(32,47), P(33,48),
	P(33,49), P(33,50), P(34,51), P(34,52), P(35,53), P(35,54), P(35,55), P(36,56),
	P(36,57), P(36,58), P(37,59), P(37,60), P(37,61), P(38,62), P(38,62), P(63,63)
};
#undef P


/**
 *
 * @param buf_size size of buf in bits
 */
void ff_init_alt1cabac_decoder(CABACContext *c, const uint8_t *buf, int buf_size){
    c->bytestream_start= buf;
    c->bytestream_end= buf + buf_size;

    c->codIOffset = bmem_peek4(buf, 0) >> 23;
    c->codIRange = 0x1fe;
    c->b_offset = 9;
}


