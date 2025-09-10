<?php
use Magento\Framework\App\Bootstrap;
require __DIR__ . '/app/bootstrap.php';
$bootstrap = Bootstrap::create(BP, $_SERVER);
$om = $bootstrap->getObjectManager();
/** @var \Magento\Theme\Model\Theme $themeModel */
$themeModel = $om->create(\Magento\Theme\Model\Theme::class);
$collection = $themeModel->getCollection();
foreach ($collection as $theme) {
    echo $theme->getId() . "\t" . $theme->getThemePath() . "\t" . $theme->getThemeTitle() . "\n";
}
