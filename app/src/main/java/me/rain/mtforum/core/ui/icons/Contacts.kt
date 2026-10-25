// Copyright 2025, compose-miuix-ui contributors
// SPDX-License-Identifier: Apache-2.0

package me.rain.mtforum.core.ui.icons

import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.PathFillType
import androidx.compose.ui.graphics.SolidColor
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.graphics.vector.PathNode
import androidx.compose.ui.graphics.vector.group
import androidx.compose.ui.unit.dp

val MiuixNavigationIcons.Contacts: ImageVector
    get() {
        if (_contactsRegular != null) return _contactsRegular!!
        _contactsRegular =
            ImageVector.Builder(
                    name = "Contacts.Regular",
                    defaultWidth = 24.0f.dp,
                    defaultHeight = 24.0f.dp,
                    viewportWidth = 1186.8f,
                    viewportHeight = 1186.8f,
                )
                .apply {
                    group(scaleY = -1.0f, translationY = 1186.8f) {
                        addPath(
                            pathData =
                                listOf(
                                    PathNode.MoveTo(1044.9f, 109.4f),
                                    PathNode.QuadTo(1068.9f, 122.4f, 1078.9f, 145.4f),
                                    PathNode.QuadTo(1084.9f, 157.4f, 1086.4f, 173.9f),
                                    PathNode.QuadTo(1087.9f, 190.4f, 1087.9f, 230.4f),
                                    PathNode.QuadTo(1087.9f, 281.4f, 1086.4f, 303.9f),
                                    PathNode.QuadTo(1084.9f, 326.4f, 1076.9f, 347.4f),
                                    PathNode.QuadTo(1069.9f, 367.4f, 1053.9f, 389.9f),
                                    PathNode.QuadTo(1037.9f, 412.4f, 1020.9f, 425.4f),
                                    PathNode.QuadTo(1003.9f, 439.4f, 986.9f, 446.9f),
                                    PathNode.QuadTo(969.9f, 454.4f, 933.9f, 466.4f),
                                    PathNode.QuadTo(767.9f, 522.4f, 593.9f, 522.4f),
                                    PathNode.QuadTo(418.9f, 522.4f, 253.9f, 466.4f),
                                    PathNode.QuadTo(216.9f, 454.4f, 199.9f, 446.9f),
                                    PathNode.QuadTo(182.9f, 439.4f, 165.9f, 425.4f),
                                    PathNode.QuadTo(148.9f, 411.4f, 132.9f, 389.4f),
                                    PathNode.QuadTo(116.9f, 367.4f, 109.9f, 347.4f),
                                    PathNode.QuadTo(101.9f, 326.4f, 100.4f, 303.9f),
                                    PathNode.QuadTo(98.9f, 281.4f, 98.9f, 230.4f),
                                    PathNode.QuadTo(98.9f, 190.4f, 100.4f, 173.9f),
                                    PathNode.QuadTo(101.9f, 157.4f, 107.9f, 145.4f),
                                    PathNode.QuadTo(117.9f, 122.4f, 141.9f, 109.4f),
                                    PathNode.QuadTo(153.9f, 103.4f, 170.9f, 101.9f),
                                    PathNode.QuadTo(187.9f, 100.4f, 226.9f, 100.4f),
                                    PathNode.HorizontalTo(959.9f),
                                    PathNode.QuadTo(998.9f, 100.4f, 1015.9f, 101.9f),
                                    PathNode.QuadTo(1032.9f, 103.4f, 1044.9f, 109.4f),
                                    PathNode.Close,
                                    PathNode.MoveTo(183.9f, 216.4f),
                                    PathNode.VerticalTo(240.4f),
                                    PathNode.QuadTo(183.9f, 272.4f, 184.9f, 286.9f),
                                    PathNode.QuadTo(185.9f, 301.4f, 190.9f, 314.4f),
                                    PathNode.QuadTo(201.9f, 340.4f, 219.9f, 355.4f),
                                    PathNode.QuadTo(230.9f, 364.4f, 242.9f, 370.4f),
                                    PathNode.QuadTo(254.9f, 376.4f, 277.9f, 383.4f),
                                    PathNode.QuadTo(422.9f, 437.4f, 583.9f, 437.4f),
                                    PathNode.QuadTo(757.9f, 437.4f, 912.9f, 375.4f),
                                    PathNode.LineTo(922.9f, 371.4f),
                                    PathNode.QuadTo(937.9f, 365.4f, 948.9f, 359.4f),
                                    PathNode.QuadTo(959.9f, 353.4f, 967.9f, 346.4f),
                                    PathNode.QuadTo(987.9f, 328.4f, 995.9f, 304.4f),
                                    PathNode.QuadTo(1000.9f, 292.4f, 1001.9f, 278.4f),
                                    PathNode.QuadTo(1002.9f, 264.4f, 1002.9f, 233.4f),
                                    PathNode.VerticalTo(216.4f),
                                    PathNode.QuadTo(1002.9f, 196.4f, 997.4f, 191.4f),
                                    PathNode.QuadTo(991.9f, 186.4f, 971.9f, 186.4f),
                                    PathNode.HorizontalTo(214.9f),
                                    PathNode.QuadTo(194.9f, 186.4f, 189.4f, 191.4f),
                                    PathNode.QuadTo(183.9f, 196.4f, 183.9f, 216.4f),
                                    PathNode.Close,
                                    PathNode.MoveTo(841.9f, 837.4f),
                                    PathNode.QuadTo(841.9f, 904.4f, 808.4f, 961.9f),
                                    PathNode.QuadTo(774.9f, 1019.4f, 717.9f, 1052.9f),
                                    PathNode.QuadTo(660.9f, 1086.4f, 593.9f, 1086.4f),
                                    PathNode.QuadTo(525.9f, 1086.4f, 468.9f, 1052.9f),
                                    PathNode.QuadTo(411.9f, 1019.4f, 378.4f, 961.9f),
                                    PathNode.QuadTo(344.9f, 904.4f, 344.9f, 837.4f),
                                    PathNode.QuadTo(344.9f, 770.4f, 378.4f, 713.4f),
                                    PathNode.QuadTo(411.9f, 656.4f, 468.9f, 622.9f),
                                    PathNode.QuadTo(525.9f, 589.4f, 593.9f, 589.4f),
                                    PathNode.QuadTo(660.9f, 589.4f, 717.9f, 622.9f),
                                    PathNode.QuadTo(774.9f, 656.4f, 808.4f, 713.4f),
                                    PathNode.QuadTo(841.9f, 770.4f, 841.9f, 837.4f),
                                    PathNode.Close,
                                    PathNode.MoveTo(429.9f, 837.4f),
                                    PathNode.QuadTo(429.9f, 881.4f, 451.9f, 918.9f),
                                    PathNode.QuadTo(473.9f, 956.4f, 511.9f, 978.4f),
                                    PathNode.QuadTo(549.9f, 1000.4f, 593.9f, 1000.4f),
                                    PathNode.QuadTo(637.9f, 1000.4f, 675.4f, 978.4f),
                                    PathNode.QuadTo(712.9f, 956.4f, 734.9f, 918.9f),
                                    PathNode.QuadTo(756.9f, 881.4f, 756.9f, 837.4f),
                                    PathNode.QuadTo(756.9f, 793.4f, 734.9f, 755.9f),
                                    PathNode.QuadTo(712.9f, 718.4f, 675.4f, 696.4f),
                                    PathNode.QuadTo(637.9f, 674.4f, 593.9f, 674.4f),
                                    PathNode.QuadTo(549.9f, 674.4f, 511.9f, 696.4f),
                                    PathNode.QuadTo(473.9f, 718.4f, 451.9f, 755.9f),
                                    PathNode.QuadTo(429.9f, 793.4f, 429.9f, 837.4f),
                                    PathNode.Close,
                                ),
                            fill = SolidColor(Color.Black),
                            fillAlpha = 1f,
                            pathFillType = PathFillType.NonZero,
                        )
                    }
                }
                .build()
        return _contactsRegular!!
    }

private var _contactsRegular: ImageVector? = null
