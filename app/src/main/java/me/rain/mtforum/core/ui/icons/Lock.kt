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

val MiuixNavigationIcons.Lock: ImageVector
    get() {
        if (_lockRegular != null) return _lockRegular!!
        _lockRegular =
            ImageVector.Builder(
                    name = "Lock.Regular",
                    defaultWidth = 24.0f.dp,
                    defaultHeight = 24.0f.dp,
                    viewportWidth = 1281.6f,
                    viewportHeight = 1281.6f,
                )
                .apply {
                    group(scaleY = -1.0f, translationY = 1281.6f) {
                        addPath(
                            pathData =
                                listOf(
                                    PathNode.MoveTo(978.8f, 123.8f),
                                    PathNode.QuadTo(1024.8f, 146.8f, 1047.8f, 192.8f),
                                    PathNode.QuadTo(1059.8f, 215.8f, 1062.3f, 248.3f),
                                    PathNode.QuadTo(1064.8f, 280.8f, 1064.8f, 357.8f),
                                    PathNode.VerticalTo(563.8f),
                                    PathNode.QuadTo(1064.8f, 640.8f, 1062.3f, 673.3f),
                                    PathNode.QuadTo(1059.8f, 705.8f, 1047.8f, 728.8f),
                                    PathNode.QuadTo(1024.8f, 773.8f, 978.8f, 796.8f),
                                    PathNode.QuadTo(964.8f, 803.8f, 947.8f, 807.3f),
                                    PathNode.QuadTo(930.8f, 810.8f, 905.8f, 812.8f),
                                    PathNode.VerticalTo(909.8f),
                                    PathNode.QuadTo(905.8f, 981.8f, 870.3f, 1042.8f),
                                    PathNode.QuadTo(834.8f, 1103.8f, 773.8f, 1139.3f),
                                    PathNode.QuadTo(712.8f, 1174.8f, 640.8f, 1174.8f),
                                    PathNode.QuadTo(568.8f, 1174.8f, 507.8f, 1139.3f),
                                    PathNode.QuadTo(446.8f, 1103.8f, 411.3f, 1042.8f),
                                    PathNode.QuadTo(375.8f, 981.8f, 375.8f, 909.8f),
                                    PathNode.VerticalTo(812.8f),
                                    PathNode.QuadTo(326.8f, 809.8f, 301.8f, 796.8f),
                                    PathNode.QuadTo(279.8f, 785.8f, 262.3f, 768.3f),
                                    PathNode.QuadTo(244.8f, 750.8f, 233.8f, 728.8f),
                                    PathNode.QuadTo(221.8f, 705.8f, 219.3f, 673.3f),
                                    PathNode.QuadTo(216.8f, 640.8f, 216.8f, 563.8f),
                                    PathNode.VerticalTo(357.8f),
                                    PathNode.QuadTo(216.8f, 280.8f, 219.3f, 248.3f),
                                    PathNode.QuadTo(221.8f, 215.8f, 233.8f, 192.8f),
                                    PathNode.QuadTo(256.8f, 146.8f, 301.8f, 123.8f),
                                    PathNode.QuadTo(324.8f, 111.8f, 357.8f, 109.3f),
                                    PathNode.QuadTo(390.8f, 106.8f, 467.8f, 106.8f),
                                    PathNode.HorizontalTo(813.8f),
                                    PathNode.QuadTo(890.8f, 106.8f, 923.3f, 109.3f),
                                    PathNode.QuadTo(955.8f, 111.8f, 978.8f, 123.8f),
                                    PathNode.Close,
                                    PathNode.MoveTo(345.8f, 200.8f),
                                    PathNode.QuadTo(322.8f, 212.8f, 310.8f, 235.8f),
                                    PathNode.QuadTo(304.8f, 246.8f, 303.3f, 262.8f),
                                    PathNode.QuadTo(301.8f, 278.8f, 301.8f, 310.8f),
                                    PathNode.VerticalTo(321.8f),
                                    PathNode.VerticalTo(599.8f),
                                    PathNode.QuadTo(301.8f, 639.8f, 303.3f, 656.3f),
                                    PathNode.QuadTo(304.8f, 672.8f, 310.8f, 684.8f),
                                    PathNode.QuadTo(322.8f, 707.8f, 345.8f, 719.8f),
                                    PathNode.QuadTo(357.8f, 725.8f, 374.8f, 727.3f),
                                    PathNode.QuadTo(391.8f, 728.8f, 430.8f, 728.8f),
                                    PathNode.HorizontalTo(849.8f),
                                    PathNode.QuadTo(889.8f, 728.8f, 906.3f, 727.3f),
                                    PathNode.QuadTo(922.8f, 725.8f, 934.8f, 719.8f),
                                    PathNode.QuadTo(958.8f, 707.8f, 970.8f, 684.8f),
                                    PathNode.QuadTo(975.8f, 672.8f, 977.3f, 656.3f),
                                    PathNode.QuadTo(978.8f, 639.8f, 978.8f, 599.8f),
                                    PathNode.VerticalTo(321.8f),
                                    PathNode.QuadTo(978.8f, 281.8f, 977.8f, 264.8f),
                                    PathNode.QuadTo(976.8f, 247.8f, 970.8f, 235.8f),
                                    PathNode.QuadTo(958.8f, 212.8f, 934.8f, 200.8f),
                                    PathNode.QuadTo(922.8f, 194.8f, 906.3f, 193.3f),
                                    PathNode.QuadTo(889.8f, 191.8f, 849.8f, 191.8f),
                                    PathNode.HorizontalTo(430.8f),
                                    PathNode.QuadTo(391.8f, 191.8f, 374.8f, 193.3f),
                                    PathNode.QuadTo(357.8f, 194.8f, 345.8f, 200.8f),
                                    PathNode.Close,
                                    PathNode.MoveTo(640.8f, 1089.8f),
                                    PathNode.QuadTo(689.8f, 1089.8f, 730.8f, 1065.3f),
                                    PathNode.QuadTo(771.8f, 1040.8f, 795.8f, 999.8f),
                                    PathNode.QuadTo(819.8f, 958.8f, 819.8f, 909.8f),
                                    PathNode.VerticalTo(814.8f),
                                    PathNode.HorizontalTo(460.8f),
                                    PathNode.VerticalTo(909.8f),
                                    PathNode.QuadTo(460.8f, 958.8f, 485.3f, 999.8f),
                                    PathNode.QuadTo(509.8f, 1040.8f, 550.8f, 1065.3f),
                                    PathNode.QuadTo(591.8f, 1089.8f, 640.8f, 1089.8f),
                                    PathNode.Close,
                                ),
                            fill = SolidColor(Color.Black),
                            fillAlpha = 1f,
                            pathFillType = PathFillType.NonZero,
                        )
                    }
                }
                .build()
        return _lockRegular!!
    }

private var _lockRegular: ImageVector? = null
