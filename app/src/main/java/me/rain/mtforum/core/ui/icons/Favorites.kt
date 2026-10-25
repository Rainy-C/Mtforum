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

val MiuixNavigationIcons.Favorites: ImageVector
    get() {
        if (_favoritesRegular != null) return _favoritesRegular!!
        _favoritesRegular =
            ImageVector.Builder(
                    name = "Favorites.Regular",
                    defaultWidth = 24.0f.dp,
                    defaultHeight = 24.0f.dp,
                    viewportWidth = 1306.8f,
                    viewportHeight = 1306.8f,
                )
                .apply {
                    group(scaleY = -1.0f, translationY = 1306.8f) {
                        addPath(
                            pathData =
                                listOf(
                                    PathNode.MoveTo(680.9f, 1071.9f),
                                    PathNode.LineTo(675.9f, 1067.9f),
                                    PathNode.LineTo(664.9f, 1056.9f),
                                    PathNode.QuadTo(652.9f, 1044.9f, 641.9f, 1056.9f),
                                    PathNode.QuadTo(634.9f, 1064.9f, 625.9f, 1071.9f),
                                    PathNode.QuadTo(583.9f, 1105.9f, 532.4f, 1124.9f),
                                    PathNode.QuadTo(480.9f, 1143.9f, 424.9f, 1143.9f),
                                    PathNode.QuadTo(338.9f, 1143.9f, 266.4f, 1101.9f),
                                    PathNode.QuadTo(193.9f, 1059.9f, 151.4f, 987.9f),
                                    PathNode.QuadTo(108.9f, 915.9f, 108.9f, 829.9f),
                                    PathNode.QuadTo(108.9f, 739.9f, 155.9f, 664.9f),
                                    PathNode.QuadTo(211.9f, 569.9f, 339.4f, 440.9f),
                                    PathNode.QuadTo(466.9f, 311.9f, 596.9f, 196.9f),
                                    PathNode.QuadTo(609.9f, 184.9f, 619.9f, 177.4f),
                                    PathNode.QuadTo(629.9f, 169.9f, 637.9f, 167.9f),
                                    PathNode.QuadTo(654.9f, 162.9f, 670.9f, 167.9f),
                                    PathNode.QuadTo(677.9f, 169.9f, 688.4f, 177.9f),
                                    PathNode.QuadTo(698.9f, 185.9f, 711.9f, 197.9f),
                                    PathNode.QuadTo(835.9f, 308.9f, 958.9f, 431.9f),
                                    PathNode.QuadTo(1081.9f, 554.9f, 1143.9f, 651.9f),
                                    PathNode.QuadTo(1197.9f, 730.9f, 1197.9f, 829.9f),
                                    PathNode.QuadTo(1197.9f, 915.9f, 1155.4f, 987.9f),
                                    PathNode.QuadTo(1112.9f, 1059.9f, 1040.9f, 1101.9f),
                                    PathNode.QuadTo(968.9f, 1143.9f, 882.9f, 1143.9f),
                                    PathNode.QuadTo(826.9f, 1143.9f, 774.9f, 1124.9f),
                                    PathNode.QuadTo(722.9f, 1105.9f, 680.9f, 1071.9f),
                                    PathNode.Close,
                                    PathNode.MoveTo(1111.9f, 829.9f),
                                    PathNode.QuadTo(1111.9f, 758.9f, 1072.9f, 699.9f),
                                    PathNode.QuadTo(1025.9f, 627.9f, 940.9f, 538.4f),
                                    PathNode.QuadTo(855.9f, 448.9f, 791.9f, 387.9f),
                                    PathNode.QuadTo(730.9f, 329.9f, 668.9f, 274.9f),
                                    PathNode.QuadTo(658.9f, 265.9f, 653.9f, 265.9f),
                                    PathNode.QuadTo(648.9f, 265.9f, 638.9f, 274.9f),
                                    PathNode.QuadTo(571.9f, 334.9f, 506.9f, 396.9f),
                                    PathNode.QuadTo(291.9f, 601.9f, 228.9f, 710.9f),
                                    PathNode.QuadTo(208.9f, 743.9f, 202.4f, 770.9f),
                                    PathNode.QuadTo(195.9f, 797.9f, 195.9f, 829.9f),
                                    PathNode.QuadTo(195.9f, 891.9f, 226.4f, 944.4f),
                                    PathNode.QuadTo(256.9f, 996.9f, 309.9f, 1027.4f),
                                    PathNode.QuadTo(362.9f, 1057.9f, 424.9f, 1057.9f),
                                    PathNode.QuadTo(472.9f, 1057.9f, 515.9f, 1038.9f),
                                    PathNode.QuadTo(558.9f, 1019.9f, 590.9f, 985.9f),
                                    PathNode.QuadTo(603.9f, 971.9f, 613.9f, 962.4f),
                                    PathNode.QuadTo(623.9f, 952.9f, 631.9f, 949.9f),
                                    PathNode.QuadTo(653.9f, 940.9f, 675.9f, 949.9f),
                                    PathNode.QuadTo(683.9f, 953.9f, 693.9f, 962.9f),
                                    PathNode.QuadTo(703.9f, 971.9f, 716.9f, 985.9f),
                                    PathNode.QuadTo(747.9f, 1019.9f, 791.4f, 1038.9f),
                                    PathNode.QuadTo(834.9f, 1057.9f, 882.9f, 1057.9f),
                                    PathNode.QuadTo(944.9f, 1057.9f, 997.9f, 1027.4f),
                                    PathNode.QuadTo(1050.9f, 996.9f, 1081.4f, 944.4f),
                                    PathNode.QuadTo(1111.9f, 891.9f, 1111.9f, 829.9f),
                                    PathNode.Close,
                                ),
                            fill = SolidColor(Color.Black),
                            fillAlpha = 1f,
                            pathFillType = PathFillType.NonZero,
                        )
                    }
                }
                .build()
        return _favoritesRegular!!
    }

private var _favoritesRegular: ImageVector? = null
