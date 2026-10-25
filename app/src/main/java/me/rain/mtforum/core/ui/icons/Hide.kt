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

val MiuixNavigationIcons.Hide: ImageVector
    get() {
        if (_hideRegular != null) return _hideRegular!!
        _hideRegular =
            ImageVector.Builder(
                    name = "Hide.Regular",
                    defaultWidth = 24.0f.dp,
                    defaultHeight = 24.0f.dp,
                    viewportWidth = 1368.0f,
                    viewportHeight = 1368.0f,
                )
                .apply {
                    group(scaleY = -1.0f, translationY = 1368.0f) {
                        addPath(
                            pathData =
                                listOf(
                                    PathNode.MoveTo(1091.0f, 257.5f),
                                    PathNode.LineTo(1109.0f, 275.5f),
                                    PathNode.QuadTo(1120.0f, 286.5f, 1119.0f, 296.5f),
                                    PathNode.QuadTo(1118.0f, 306.5f, 1107.0f, 317.5f),
                                    PathNode.LineTo(314.0f, 1111.5f),
                                    PathNode.QuadTo(304.0f, 1121.5f, 293.5f, 1122.0f),
                                    PathNode.QuadTo(283.0f, 1122.5f, 271.0f, 1110.5f),
                                    PathNode.LineTo(256.0f, 1095.5f),
                                    PathNode.QuadTo(244.0f, 1083.5f, 243.0f, 1073.0f),
                                    PathNode.QuadTo(242.0f, 1062.5f, 255.0f, 1049.5f),
                                    PathNode.LineTo(1049.0f, 255.5f),
                                    PathNode.QuadTo(1059.0f, 245.5f, 1069.5f, 246.0f),
                                    PathNode.QuadTo(1080.0f, 246.5f, 1091.0f, 257.5f),
                                    PathNode.Close,
                                    PathNode.MoveTo(888.0f, 305.5f),
                                    PathNode.LineTo(821.0f, 373.5f),
                                    PathNode.QuadTo(752.0f, 353.5f, 684.0f, 353.5f),
                                    PathNode.QuadTo(586.0f, 353.5f, 490.5f, 393.5f),
                                    PathNode.QuadTo(395.0f, 433.5f, 319.0f, 504.0f),
                                    PathNode.QuadTo(243.0f, 574.5f, 202.0f, 664.5f),
                                    PathNode.QuadTo(196.0f, 680.5f, 202.0f, 694.5f),
                                    PathNode.QuadTo(224.0f, 742.5f, 256.0f, 785.0f),
                                    PathNode.QuadTo(288.0f, 827.5f, 329.0f, 864.5f),
                                    PathNode.LineTo(269.0f, 925.5f),
                                    PathNode.QuadTo(223.0f, 883.5f, 186.0f, 834.5f),
                                    PathNode.QuadTo(149.0f, 785.5f, 125.0f, 730.5f),
                                    PathNode.QuadTo(114.0f, 706.5f, 114.0f, 680.0f),
                                    PathNode.QuadTo(114.0f, 653.5f, 125.0f, 629.5f),
                                    PathNode.QuadTo(172.0f, 524.5f, 260.0f, 442.0f),
                                    PathNode.QuadTo(348.0f, 359.5f, 459.0f, 313.5f),
                                    PathNode.QuadTo(570.0f, 267.5f, 684.0f, 267.5f),
                                    PathNode.QuadTo(784.0f, 267.5f, 888.0f, 305.5f),
                                    PathNode.Close,
                                    PathNode.MoveTo(734.0f, 460.5f),
                                    PathNode.LineTo(651.0f, 544.5f),
                                    PathNode.QuadTo(630.0f, 548.5f, 612.0f, 559.5f),
                                    PathNode.QuadTo(594.0f, 570.5f, 580.0f, 585.5f),
                                    PathNode.QuadTo(555.0f, 611.5f, 546.0f, 648.5f),
                                    PathNode.LineTo(463.0f, 732.5f),
                                    PathNode.QuadTo(457.0f, 707.5f, 457.0f, 681.5f),
                                    PathNode.QuadTo(457.0f, 619.5f, 487.5f, 567.5f),
                                    PathNode.QuadTo(518.0f, 515.5f, 570.0f, 485.0f),
                                    PathNode.QuadTo(622.0f, 454.5f, 683.0f, 454.5f),
                                    PathNode.QuadTo(710.0f, 454.5f, 734.0f, 460.5f),
                                    PathNode.Close,
                                    PathNode.MoveTo(486.0f, 1056.5f),
                                    PathNode.LineTo(555.0f, 988.5f),
                                    PathNode.QuadTo(624.0f, 1006.5f, 684.0f, 1006.5f),
                                    PathNode.QuadTo(783.0f, 1006.5f, 878.5f, 967.0f),
                                    PathNode.QuadTo(974.0f, 927.5f, 1049.0f, 856.5f),
                                    PathNode.QuadTo(1124.0f, 785.5f, 1165.0f, 695.5f),
                                    PathNode.QuadTo(1171.0f, 681.5f, 1165.0f, 665.5f),
                                    PathNode.QuadTo(1124.0f, 575.5f, 1043.0f, 500.5f),
                                    PathNode.LineTo(1103.0f, 439.5f),
                                    PathNode.QuadTo(1193.0f, 522.5f, 1243.0f, 630.5f),
                                    PathNode.QuadTo(1254.0f, 654.5f, 1254.0f, 681.0f),
                                    PathNode.QuadTo(1254.0f, 707.5f, 1243.0f, 731.5f),
                                    PathNode.QuadTo(1196.0f, 835.5f, 1108.5f, 917.5f),
                                    PathNode.QuadTo(1021.0f, 999.5f, 910.0f, 1045.5f),
                                    PathNode.QuadTo(799.0f, 1091.5f, 684.0f, 1091.5f),
                                    PathNode.QuadTo(583.0f, 1091.5f, 486.0f, 1056.5f),
                                    PathNode.Close,
                                    PathNode.MoveTo(641.0f, 901.5f),
                                    PathNode.LineTo(730.0f, 812.5f),
                                    PathNode.QuadTo(762.0f, 800.5f, 781.0f, 781.5f),
                                    PathNode.QuadTo(794.0f, 769.5f, 803.5f, 755.0f),
                                    PathNode.QuadTo(813.0f, 740.5f, 818.0f, 723.5f),
                                    PathNode.LineTo(906.0f, 634.5f),
                                    PathNode.QuadTo(911.0f, 659.5f, 911.0f, 679.5f),
                                    PathNode.QuadTo(911.0f, 740.5f, 880.5f, 792.5f),
                                    PathNode.QuadTo(850.0f, 844.5f, 798.0f, 875.0f),
                                    PathNode.QuadTo(746.0f, 905.5f, 684.0f, 905.5f),
                                    PathNode.QuadTo(660.0f, 905.5f, 641.0f, 901.5f),
                                    PathNode.Close,
                                ),
                            fill = SolidColor(Color.Black),
                            fillAlpha = 1f,
                            pathFillType = PathFillType.NonZero,
                        )
                    }
                }
                .build()
        return _hideRegular!!
    }

private var _hideRegular: ImageVector? = null
