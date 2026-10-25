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

val MiuixNavigationIcons.Show: ImageVector
    get() {
        if (_showRegular != null) return _showRegular!!
        _showRegular =
            ImageVector.Builder(
                    name = "Show.Regular",
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
                                    PathNode.MoveTo(1243.0f, 633.5f),
                                    PathNode.QuadTo(1254.0f, 657.5f, 1254.0f, 684.0f),
                                    PathNode.QuadTo(1254.0f, 710.5f, 1243.0f, 734.5f),
                                    PathNode.QuadTo(1196.0f, 839.5f, 1108.5f, 921.5f),
                                    PathNode.QuadTo(1021.0f, 1003.5f, 910.0f, 1049.5f),
                                    PathNode.QuadTo(799.0f, 1095.5f, 684.0f, 1095.5f),
                                    PathNode.QuadTo(568.0f, 1095.5f, 457.5f, 1049.5f),
                                    PathNode.QuadTo(347.0f, 1003.5f, 259.5f, 921.5f),
                                    PathNode.QuadTo(172.0f, 839.5f, 125.0f, 734.5f),
                                    PathNode.QuadTo(114.0f, 710.5f, 114.0f, 684.0f),
                                    PathNode.QuadTo(114.0f, 657.5f, 125.0f, 633.5f),
                                    PathNode.QuadTo(172.0f, 528.5f, 260.0f, 446.5f),
                                    PathNode.QuadTo(348.0f, 364.5f, 459.0f, 318.5f),
                                    PathNode.QuadTo(570.0f, 272.5f, 684.0f, 272.5f),
                                    PathNode.QuadTo(798.0f, 272.5f, 908.5f, 318.5f),
                                    PathNode.QuadTo(1019.0f, 364.5f, 1107.0f, 446.5f),
                                    PathNode.QuadTo(1195.0f, 528.5f, 1243.0f, 633.5f),
                                    PathNode.Close,
                                    PathNode.MoveTo(202.0f, 669.5f),
                                    PathNode.QuadTo(196.0f, 683.5f, 202.0f, 699.5f),
                                    PathNode.QuadTo(243.0f, 789.5f, 318.5f, 860.0f),
                                    PathNode.QuadTo(394.0f, 930.5f, 489.5f, 970.0f),
                                    PathNode.QuadTo(585.0f, 1009.5f, 684.0f, 1009.5f),
                                    PathNode.QuadTo(783.0f, 1009.5f, 878.5f, 970.0f),
                                    PathNode.QuadTo(974.0f, 930.5f, 1049.0f, 859.5f),
                                    PathNode.QuadTo(1124.0f, 788.5f, 1165.0f, 699.5f),
                                    PathNode.QuadTo(1171.0f, 683.5f, 1165.0f, 669.5f),
                                    PathNode.QuadTo(1124.0f, 579.5f, 1048.0f, 508.5f),
                                    PathNode.QuadTo(972.0f, 437.5f, 876.5f, 397.5f),
                                    PathNode.QuadTo(781.0f, 357.5f, 684.0f, 357.5f),
                                    PathNode.QuadTo(586.0f, 357.5f, 490.5f, 397.5f),
                                    PathNode.QuadTo(395.0f, 437.5f, 319.0f, 508.5f),
                                    PathNode.QuadTo(243.0f, 579.5f, 202.0f, 669.5f),
                                    PathNode.Close,
                                    PathNode.MoveTo(910.0f, 683.5f),
                                    PathNode.QuadTo(910.0f, 745.5f, 879.5f, 797.5f),
                                    PathNode.QuadTo(849.0f, 849.5f, 797.0f, 880.0f),
                                    PathNode.QuadTo(745.0f, 910.5f, 684.0f, 910.5f),
                                    PathNode.QuadTo(623.0f, 910.5f, 571.0f, 880.0f),
                                    PathNode.QuadTo(519.0f, 849.5f, 488.5f, 797.5f),
                                    PathNode.QuadTo(458.0f, 745.5f, 458.0f, 683.5f),
                                    PathNode.QuadTo(458.0f, 622.5f, 488.5f, 570.5f),
                                    PathNode.QuadTo(519.0f, 518.5f, 571.0f, 488.0f),
                                    PathNode.QuadTo(623.0f, 457.5f, 684.0f, 457.5f),
                                    PathNode.QuadTo(745.0f, 457.5f, 797.0f, 488.0f),
                                    PathNode.QuadTo(849.0f, 518.5f, 879.5f, 570.5f),
                                    PathNode.QuadTo(910.0f, 622.5f, 910.0f, 683.5f),
                                    PathNode.Close,
                                    PathNode.MoveTo(543.0f, 683.5f),
                                    PathNode.QuadTo(543.0f, 721.5f, 562.0f, 754.0f),
                                    PathNode.QuadTo(581.0f, 786.5f, 613.5f, 805.5f),
                                    PathNode.QuadTo(646.0f, 824.5f, 684.0f, 824.5f),
                                    PathNode.QuadTo(722.0f, 824.5f, 754.5f, 805.5f),
                                    PathNode.QuadTo(787.0f, 786.5f, 806.0f, 754.0f),
                                    PathNode.QuadTo(825.0f, 721.5f, 825.0f, 683.5f),
                                    PathNode.QuadTo(825.0f, 645.5f, 806.0f, 613.0f),
                                    PathNode.QuadTo(787.0f, 580.5f, 754.5f, 561.5f),
                                    PathNode.QuadTo(722.0f, 542.5f, 684.0f, 542.5f),
                                    PathNode.QuadTo(646.0f, 542.5f, 613.5f, 561.5f),
                                    PathNode.QuadTo(581.0f, 580.5f, 562.0f, 613.0f),
                                    PathNode.QuadTo(543.0f, 645.5f, 543.0f, 683.5f),
                                    PathNode.Close,
                                ),
                            fill = SolidColor(Color.Black),
                            fillAlpha = 1f,
                            pathFillType = PathFillType.NonZero,
                        )
                    }
                }
                .build()
        return _showRegular!!
    }

private var _showRegular: ImageVector? = null
